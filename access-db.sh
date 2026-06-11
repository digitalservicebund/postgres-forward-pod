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
RANDOM_SUFFIX=$(hexdump -n 6 -e '6/1 "%02x"' /dev/urandom)
PGUSER="temp_$(whoami)_$RANDOM_SUFFIX"
# command line args
CFG=$1
# mode can be psql or background
MODE=${2}

if [ -z "$CFG" ]; then
    echo "Usage: ./access-db.sh <config_file> [psql|bg]\nIf mode is 'psql', launches a psql shell. If mode is 'bg', runs in background mode (i.e. for use with other tools like IntelliJ)."
    exit 1
fi

# load config from file, will load unnecessary vars that are used by child script but it doesn't matter
_load_config "$CFG"

kubectl config use-context "${KUBE_CONTEXT}" >/dev/null || {
    exit 1
}
kubectl get namespace "$NAMESPACE" >/dev/null || {
    exit 1
}

if [ -z "$PROJECT_ID" ] || [ -z "$INSTANCE_NAME" ]; then
    echo "Config must define PROJECT_ID and INSTANCE_NAME."
    exit 1
fi

# extract instance id from stackit command line
INSTANCE_ID=$(stackit postgresqlflex instance list --project-id="$PROJECT_ID" -o json | jq -r --arg name "$INSTANCE_NAME" '.[] | select(.name == $name) | .id')
if [ -z "$INSTANCE_ID" ]; then
    echo "Error: Could not find STACKIT instance '${INSTANCE_NAME}' in project '${PROJECT_ID}'."
    exit 1
fi

if [ -n "$SECRET_NAME" ]; then
    PGUSER=$DB_USERNAME
    PGPASSWORD=$(kubectl get secret "$SECRET_NAME" --namespace "$NAMESPACE" -o jsonpath="{.data.${DB_USERNAME}_password}" | base64 --decode)
    # extract user id from stackit command line
    USER_ID=$(stackit postgresqlflex user list --project-id="$PROJECT_ID" --instance-id="$INSTANCE_ID" -o json | jq -r --arg name "$DB_USERNAME" '.[] | select(.username == $name) | .id')
else
    # create user
    USER_DETAILS=$(stackit postgresqlflex user create --username "$PGUSER" --project-id "$PROJECT_ID" --instance-id "$INSTANCE_ID" --output-format json -y)
    USER_ID=$(echo "$USER_DETAILS" | jq -r '.item.id')
    PGPASSWORD=$(echo "$USER_DETAILS" | jq -r '.item.password')
fi

# extract host and port from the user
USER_BLOB=$(stackit postgresqlflex user describe "$USER_ID" --project-id="$PROJECT_ID" --instance-id="$INSTANCE_ID" -o json)

# export vars for child script
export DATABASE_HOST=$(echo $USER_BLOB | jq -r '.host')
export DATABASE_PORT=$(echo $USER_BLOB | jq -r '.port')
export SUFFIX="$RANDOM_SUFFIX" # matches temporary user if being used

# cleanup deletes the user and tears down the pod, runs on all exits with a trap
cleanup() {
    trap - EXIT INT TERM
    ./db-forward.sh "$CFG" down
    if [ -n "$USER_DETAILS" ]; then
        stackit postgresqlflex user delete --project-id $PROJECT_ID --instance-id $INSTANCE_ID -y $USER_ID
    fi
    echo "Teardown complete."
    exit
}

trap cleanup EXIT INT TERM

./db-forward.sh $CFG up

case "$(echo "$MODE" | tr '[:upper:]' '[:lower:]')" in
psql)
    sleep 1 # seems to need a delay here or we get connection refused
    PGPASSWORD=$PGPASSWORD psql -h localhost -p $DATABASE_LOCAL_PORT -U "$PGUSER" -d $DATABASE_NAME
    ;;
bg)
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
        printf "You can connect to the database on localhost:$DATABASE_LOCAL_PORT with the above credentials.\n"
        ;;
    esac
    echo "Running in background mode. Press Ctrl+C to stop and cleanup user and pod."
    while true; do sleep 1; done
    ;;
esac
