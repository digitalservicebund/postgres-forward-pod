#!/usr/bin/env sh

_load_config() {
    _config="${1}"

	while read -r _line || test -n "${_line}"; do
		if test -n "${_line}"; then
			# shellcheck disable=SC2163
			export "${_line}"
		fi
		# no else: ignore empty line
	done <"${_config}"
}

# generate random username
PGUSER="temp_$(hexdump -n 6 -e '6/1 "%02x"' /dev/urandom)"
# command line args
CFG=$1
# mode can be shell or background
DATABASE_NAME=${2}

if [ -z "$CFG" ]; then
    echo "Usage: ./access-db.sh <config_file> [database_name]\nIf database_name specified, launches psql shell, otherwise, runs in background mode (i.e. for use with other tools like IntelliJ).";
    exit 1;
fi

# load config from file, will load unnecessary vars that are used by child script but it doesn't matter
_load_config "$CFG"

if [ -z "$PROJECT_ID" ] || [ -z "$INSTANCE_ID" ]; then
    echo "Config must define PROJECT_ID and INSTANCE_ID.";
    exit 1;
fi

# create user
USER_DETAILS=$(stackit postgresqlflex user create --username "$PGUSER" --project-id $PROJECT_ID --instance-id $INSTANCE_ID --output-format json -y)

USERID=$(echo "$USER_DETAILS" | jq -r '.item.id')
PGPASSWORD=$(echo "$USER_DETAILS" | jq -r '.item.password')

# cleanup deletes the user and tears down the pod, runs on all exits with a trap
cleanup() {
    trap - EXIT INT TERM
    ./db-forward.sh $CFG down
    stackit postgresqlflex user delete --project-id $PROJECT_ID --instance-id $INSTANCE_ID -y $USERID
    echo "User and pod deleted."
    exit
}

trap cleanup EXIT INT TERM

./db-forward.sh $CFG up

if [ -n "$DATABASE_NAME" ]; then
    sleep 1 # seems to need a delay here or we get connection refused
    PGPASSWORD=$PGPASSWORD psql -h localhost -p $DATABASE_LOCAL_PORT -U "$PGUSER" -d $DATABASE_NAME
else
    echo "##############################################################################"
    echo "# Use the following credentials:                                             #"
    echo "# username: $PGUSER                                                #"
    echo "# password: $PGPASSWORD #"
    echo "# Running in background mode. Press Ctrl+C to stop and cleanup user and pod. #"
    echo "##############################################################################"
    while true; do sleep 1; done
fi
