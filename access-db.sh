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
    echo "Usage: ./access-db.sh <config_file> [database_name]\nIf database_name specified, launches psql shell, otherwise, runs in background mode (i.e. for use with other tools like IntelliJ)."
    exit 1
fi

# load config from file, will load unnecessary vars that are used by child script but it doesn't matter
_load_config "$CFG"

if [ -z "$PROJECT_ID" ] || [ -z "$INSTANCE_ID" ]; then
    echo "Config must define PROJECT_ID and INSTANCE_ID."
    exit 1
fi

if [ -n "$SECRET_NAME" ]; then
    PGUSER=$DB_USERNAME
    PGPASSWORD=$(kubectl get secret $SECRET_NAME --namespace $NAMESPACE -o jsonpath="{.data.${DB_USERNAME}_password}" | base64 --decode)
else
    # create user
    USER_DETAILS=$(stackit postgresqlflex user create --username "$PGUSER" --project-id $PROJECT_ID --instance-id $INSTANCE_ID --output-format json -y)

    USERID=$(echo "$USER_DETAILS" | jq -r '.item.id')
    PGPASSWORD=$(echo "$USER_DETAILS" | jq -r '.item.password')
fi

# cleanup deletes the user and tears down the pod, runs on all exits with a trap
cleanup() {
    trap - EXIT INT TERM
    ./db-forward.sh $CFG down
    if [ -n "$USER_DETAILS" ]; then
        stackit postgresqlflex user delete --project-id $PROJECT_ID --instance-id $INSTANCE_ID -y $USERID
    fi
    echo "Teardown complete."
    exit
}

trap cleanup EXIT INT TERM

./db-forward.sh $CFG up

if [ -n "$DATABASE_NAME" ]; then
    sleep 1 # seems to need a delay here or we get connection refused
    PGPASSWORD=$PGPASSWORD psql -h localhost -p $DATABASE_LOCAL_PORT -U "$PGUSER" -d $DATABASE_NAME
else
    printf "Display credentials? [y/N] "
    read -r _confirm
    case "$_confirm" in
    [yY])
        _ulen=${#PGUSER}
        _plen=${#PGPASSWORD}
        if [ "$_ulen" -gt "$_plen" ]; then _mlen=$_ulen; else _mlen=$_plen; fi
        _border=$(printf '%*s' "$((_mlen + 14))" | tr ' ' '#')
        printf '%s\n' "$_border"
        printf "# username: %-*s #\n" "$_mlen" "$PGUSER"
        printf "# password: %-*s #\n" "$_mlen" "$PGPASSWORD"
        printf '%s\n' "$_border"
        ;;
    esac
    echo "Running in background mode. Press Ctrl+C to stop and cleanup user and pod."
    while true; do sleep 1; done
fi
