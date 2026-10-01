#!/bin/bash

set -o pipefail

LOG_FILE="$(mktemp)"

# Color codes
NONE="\e[0m"
BLACK="\e[30m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
PURPLE="\e[35m"
CYAN="\e[36m"

trap "exit 1" SIGINT

# Print info
function info {
    echo -e "[${CYAN}+${NONE}] $@"
    echo -e "[+] $@" >>$LOG_FILE
}

# Print notify
function notify {
    echo -e "  [${GREEN}!${NONE}] $@"
    echo -e "  [!] $@" >>$LOG_FILE
}

# Ask for input
function ask {
    echo -e -n "[${YELLOW}?${NONE}] $1 " 1>&2
    echo -e -n "[?] $1 " >>$LOG_FILE

    if [ "_$NO_CONFIRM" != "_" ]; then
        echo "$2"
        echo "$2" 1>&2
        echo "$2" >>$LOG_FILE
    else
        read -r value
        echo "$value" >>$LOG_FILE
        if [ "_$value" == "_" ]; then
            echo "$2"
            echo "$2" >>$LOG_FILE
        else
            echo "$value"
            echo "$value" >>$LOG_FILE
        fi
    fi
}

# Ask for retry
function retry {
    echo -e -n "[${RED}!${NONE}] Failed. Show additional log? [y/N] " 1>&2
    echo -e -n "[!] Failed. Show additional log? [y/N] " >>$LOG_FILE

    if [ "_$NO_CONFIRM" != "_" ]; then
        echo "N" 1>&2
        echo "N" >>$LOG_FILE
        tail -n 40 $LOG_FILE
        false
    else
        read -r value1
        echo "$value1" >>$LOG_FILE
        if [ "_$value1" == "_y" ] || [ "_$value1" == "_Y" ]; then
            less $LOG_FILE
        fi
        echo -e -n "[${RED}?${NONE}] Retry? [Y/n] " 1>&2
        echo -e -n "[?] Retry? [Y/n] " >>$LOG_FILE
        read -r value2
        echo "$value2" >>$LOG_FILE
        if [ "_$value2" == "_n" ] || [ "_$value2" == "_N" ]; then
            false
        else
            true
        fi
    fi
}

# Ask for termination
function terminate {
    echo -e -n "[${RED}?${NONE}] Terminate? [Y/n] " 1>&2
    echo -e -n "[?] Terminate? [Y/n] " >>$LOG_FILE

    if [ "_$NO_CONFIRM" != "_" ]; then
        exit 1
    fi

    read -r value
    echo "$value" >>$LOG_FILE
    if [ "_$value" == "_n" ] || [ "_$value" == "_N" ]; then
        false
    else
        exit 1
    fi
}

# Warn the user
function warn {
    echo -e "[${RED}!${NONE}] $@"
    echo -e "[!] $@" >>$LOG_FILE
}

# Report error
function error {
    echo -e "[${RED}!${NONE}] $@"
    echo -e "[!] $@" >>$LOG_FILE
}

# Execute a command in a subshell. Honors STDOUT, STDERR (cout/cerr = terminal)
# and the PIPE array. Arguments: $1 = working dir, rest = command.
function _exec_cmd {
    local dir="$1"
    shift
    (
        cd "$dir" || exit 1
        [ "_$STDOUT" == "_cout" ] || exec >>"$STDOUT"
        [ "_$STDERR" == "_cerr" ] || exec 2>>"$STDERR"
        if [ ${#PIPE[@]} -gt 0 ]; then
            "$@" | "${PIPE[@]}"
        else
            "$@"
        fi
    )
}

# Run a command, ask to retry on failure
function run_with_retry {
    local dir="${DIR:-$(pwd)}"
    local exitcode=0
    STDOUT="${STDOUT:-$LOG_FILE}"
    STDERR="${STDERR:-$LOG_FILE}"

    while true; do
        notify "Execute '${CYAN}$*${NONE}'"
        _exec_cmd "$dir" "$@" &
        local pid=$!
        (
            secs=0
            while sleep 1; do
                secs=$((secs + 1))
                echo -en "\r      Progress: ${YELLOW}${secs}s${NONE}     "
            done
        ) &
        local ticker=$!
        wait "$pid"
        exitcode=$?
        kill "$ticker" 2>/dev/null
        wait "$ticker" 2>/dev/null
        echo -en "\r"
        [ "$exitcode" -eq 0 ] && break || retry || terminate || break
    done

    unset PIPE
    unset STDOUT
    unset STDERR
    return "$exitcode"
}

# Run a command once
function run_once {
    local dir="${DIR:-$(pwd)}"
    local exitcode=0
    STDOUT="${STDOUT:-$LOG_FILE}"
    STDERR="${STDERR:-$LOG_FILE}"

    notify "Execute '${CYAN}$*${NONE}'"
    _exec_cmd "$dir" "$@" || exitcode=$?

    unset PIPE
    unset STDOUT
    unset STDERR
    return "$exitcode"
}

# Install neovim LSP
function nvim_install_lsp {
    if [ ! -z "$(which nvim)" ]; then
        run_with_retry nvim --headless -c "MasonInstall $1" -c "quitall"
    fi
}

# Check for proxy
function check_proxy {
    resp=$(ask "Behind a proxy? [y/N]" "N")
    if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
        let missing=1
        if [ "_$http_proxy" == "_" ]; then
            missing=0
            error "Environment '${RED}\$http_proxy${NONE}' is empty!"
        else
            info "Environment '\$http_proxy' is '$http_proxy'"
        fi
        if [ "_$https_proxy" == "_" ]; then
            missing=0
            error "Environment '${RED}\$https_proxy${NONE}' is empty!"
        else
            info "Environment '\$https_proxy' is '$https_proxy'"
        fi
        if [ $missing ]; then
            error "${RED}Fill missing proxy environment variables.${NONE}"
            exit 0
        fi
    fi
}

# Check for sudo
function check_sudo {
    info "Check for root privileges.."
    if [ ! -z "$(whoami)" ]; then
        if [ "$(whoami)" != "root" ]; then
            if [ ! -z "$(which sudo 2>/dev/null)" ]; then
                export SUDO=sudo
            fi
            if [ -z "$SUDO" ]; then
                echo "Looks like you aren't root but also sudo isn't present. Proceeding for now..."
            else
                sudo echo -n "" || exit
            fi
        fi
    else
        echo "Could NOT detect user. Root privileges required. Proceeding for now..."
    fi
}

function delete_log {
    if [ -f "$LOG_FILE" ]; then
        rm -rf "$LOG_FILE"
    fi
}

# Initialize log
touch $LOG_FILE
info "Logging into ${LOG_FILE}."
