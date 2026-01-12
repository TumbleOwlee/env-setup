#!/bin/bash

NONE="\e[0m"
BLACK="\e[30m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
PURPLE="\e[35m"
CYAN="\e[36m"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

if ! command -v which >/dev/null 2>&1
then
    echo "'which' could not be found"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1
then
    echo "'curl' could not be found"
    exit 1
fi

# Check for sudo
function check_sudo {
    echo -e "[${CYAN}+${NONE}] Check for root privileges.."
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

check_sudo

function is_arch {
    if type "yay" 2>/dev/null >/dev/null; then
        return 0
    else
        if type "pacman" 2>/dev/null >/dev/null; then
            return 0
        else
            return 1
        fi
    fi
}

function is_ubuntu {
    if type "apt" 2>/dev/null >/dev/null; then
        return 0
    else
        return 1
    fi
}

function sim_exit {
    if [ -z "$1" ]; then
        return 1
    else
        return $1
    fi
}

function run_async() {
    local cmd=""
    for idx in $(seq $#); do
        if [ -z "$cmd" ]; then
            cmd="$cmd${!idx}"
        else
            cmd="$cmd%${!idx}"
        fi
    done

    if [ -z "$DIR" ]; then
        DIR="$(pwd)"
    fi

    echo -e "[${CYAN}+${NONE}] Execute '${CYAN}$@${NONE}'"
    local IFS='%'
    tmpfile=$(mktemp)
    {
        cd "$DIR" && $cmd &>/dev/null
        echo -n $? >$tmpfile
    } &
    SECONDS=0
    while [ -z "$(cat $tmpfile)" ]; do
        if [ $SECONDS -gt 0 ]; then
            echo -en "    Progress: ${YELLOW}${SECONDS}s${NONE}     \r"
        fi
    done
    exitcode=$(cat $tmpfile)
    rm $tmpfile
    sim_exit $exitcode || exit 1
}

for i in "$@"; do
    case $i in
    -d | --debug)
        export DEBUG=y
        ;;
    *) ;;
    esac
done

if is_arch; then
    if [ -z "$DEBUG" ]; then
        source <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Arch/setup.sh 2>/dev/null) $@
    else
        echo -e "[${YELLOW}?${NONE}] Debug mode active." 1>&2
        source "$SCRIPT_DIR/Arch/setup.sh"
    fi
elif is_ubuntu; then
    if [ -z "$DEBUG" ]; then
        source <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Ubuntu/setup.sh 2>/dev/null) $@
    else
        echo -e "[${YELLOW}?${NONE}] Debug mode active." 1>&2
        source "$SCRIPT_DIR/Ubuntu/setup.sh"
    fi
fi
