#!/usr/bin/env sh

# run with care AND hack with care (especially if you have kubernetes production access)

# the config file are hackilly parsed and every non empty line will be fed into an export command

### example config begin
# KUBE_CONTEXT=dev
# NAMESPACE=ris-staging
# SUFFIX=janedoe
# DATABASE_HOST=10.1.2.3
# DATABASE_REMOTE_PORT=5432
# DATABASE_LOCAL_PORT=55432
### example config end

_DEBUG_MODE="off"

_debug() {
    test "$_DEBUG_MODE" = "on" &&  $@
}

_load_config() {
    _config="${1}"

    while read -r _line || test -n "${_line}"
    do
        if test -n "${_line}"
        then
            export "${_line}" 
        fi
        # no else: ignore empty line
    done < "${_config}"

    printf 'KUBE_CONTEXT:%s\n' "${KUBE_CONTEXT}"
    printf 'NAMESPACE:%s\n' "${NAMESPACE}"
    printf 'SUFFIX:%s\n' "${SUFFIX}"
    printf 'DATABASE_HOST:%s\n' "${DATABASE_HOST}"
    printf 'DATABASE_REMOTE_PORT:%s\n' "${DATABASE_REMOTE_PORT}"
    printf 'DATABASE_LOCAL_PORT:%s\n' "${DATABASE_LOCAL_PORT}"
}

_check_kubectl_ok() {
    kubectl version --output json >/dev/null 2>&1
    if test "$?" -ne 0
    then
        printf 'NOK'
    else
        printf 'OK'
    fi
}

_check_config_ok() {
    if test -f "${_config}"
    then
        printf 'OK' 
    else
        printf 'NOK'
    fi
}

_check_sub_command_ok() {
    _sub_command="${1}"

    if test "#${_sub_command}#" = "#up#"
    then
        printf 'OK'
    elif test "#${_sub_command}#" = "#down#"
    then
        printf 'OK'
    else
        printf 'NOK'
    fi
}

_run_up() {
    _config="${1}"

    _load_config "${_config}"

    kubectl config use-context "${KUBE_CONTEXT}"
    
    envsubst < manifest.yaml | kubectl apply -n "${NAMESPACE}" -f -
    
    printf 'Waiting for pod to run ...\n'
    kubectl --namespace="${NAMESPACE}" wait --for=jsonpath='{.status.phase}'=Running pod/postgres-forward-pod-$SUFFIX
    
    printf 'Starting port forwarding ...\n'
    nohup kubectl --namespace="${NAMESPACE}" port-forward pod/postgres-forward-pod-$SUFFIX $DATABASE_LOCAL_PORT:$DATABASE_REMOTE_PORT >/dev/null 2>&1 &

    printf 'Check for running port-foward process:\n'
    pgrep --list-full --full "kubectl --namespace="${NAMESPACE}" port-forward pod/postgres-forward-pod-$SUFFIX $DATABASE_LOCAL_PORT:$DATABASE_REMOTE_PORT"

    printf 'Done.\n'
}

_run_down() {
    _config="${1}"

    _load_config "${_config}"

    kubectl config use-context "${KUBE_CONTEXT}"
    
    printf 'Stopping port forwarding ...\n'
    pkill --full "kubectl --namespace="${NAMESPACE}" port-forward pod/postgres-forward-pod-$SUFFIX $DATABASE_LOCAL_PORT:$DATABASE_REMOTE_PORT"
    
    envsubst < manifest.yaml | kubectl delete -n "${NAMESPACE}" -f -
    
    printf 'Waiting until pod is gone ...\n'
    kubectl --namespace="${NAMESPACE}" wait --for=delete pod/postgres-forward-pod-$SUFFIX
    
    printf 'Done.\n'
}

_show_current_port_forward_procs() {
    printf 'Processes containing "port-forward" in their command line:\n'
    pgrep --list-full --full 'port-forward'
    printf '.\n'
}

_run_with_config() {
    _config="${1}"
    _sub_command="${2}"

    "_run_${_sub_command}" "${_config}"
}

_main() {
    _config="${1}"
    _sub_command="${2}"

    if test $# -lt 2
    then
        printf 'Usage: db-forward-up <config-file> <up|down>\n.\n'
        _show_current_port_forward_procs

    elif test `_check_kubectl_ok` != "OK"
    then
        printf 'ERROR: kubectl seems to have no cluster access. Check with "kubectl version".\n'

    elif test `_check_config_ok "${_config}"` != "OK"
    then
        printf 'ERROR: config file not ok: %s\n' "${_config}"

    elif test `_check_sub_command_ok "${_sub_command}"` != "OK"
    then
        printf 'ERROR: second parameter subcommand must be one of "up" or "down" but was:%s\n' "${_sub_command}"

    else
        _run_with_config "${_config}" "${_sub_command}"
        #_debug echo "${_config} - ${_sub_command}"
    fi
}

_main $@
