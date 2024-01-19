#!/bin/bash

LOG_FILE="/tmp/setup_$(date +%Y_%m_%d_%H_%M_%S).log"

# Color codes
NONE="\e[0m";    BLACK="\e[30m"; RED="\e[31m";    GREEN="\e[32m"
YELLOW="\e[33m"; BLUE="\e[34m";  PURPLE="\e[35m"; CYAN="\e[36m"

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
    read value
    echo "$value" >>$LOG_FILE
    if [ "_$value" == "_" ]; then
        echo "$2"
        echo "$2" >>$LOG_FILE
    else
        echo "$value"
        echo "$value" >>$LOG_FILE
    fi
}

# Ask for retry
function retry {
    echo -e -n "[${RED}!${NONE}] Failed. Show additional log? [y/N] " 1>&2
    echo -e -n "[!] Failed. Show additional log? [y/N] " >>$LOG_FILE
    read value1
    echo "$value1" >>$LOG_FILE
    if [ "_$value1" == "_y" ] || [ "_$value1" == "_Y" ]; then
        less $LOG_FILE
    fi
    echo -e -n "[${RED}?${NONE}] Retry? [Y/n] " 1>&2
    echo -e -n "[?] Retry? [Y/n] " >>$LOG_FILE
    read value2
    echo "$value2" >>$LOG_FILE
    if [ "_$value2" == "_n" ] || [ "_$value2" == "_N" ]; then
        false
    else
        true
    fi
}

# Ask for termination
function terminate {
    echo -e -n "[${RED}?${NONE}] Terminate? [Y/n] " 1>&2
    echo -e -n "[?] Terminate? [Y/n] " >>$LOG_FILE
    read value
    echo "$value" >>$LOG_FILE
    if [ "_$value" == "_n" ] || [ "_$value" == "_N" ]; then
        false
    else
        exit 0
    fi
}

# Warn the user
function warn {
    echo -e "[${RED}!${NONE}] ${YELLOW}$@${NONE}"
    echo -e "[!] $@" >>$LOG_FILE
}

function run_with_retry {
    local cmd=""
    for idx in $(seq $#); do
        if [ "_$cmd" == "_" ]; then
            cmd="$cmd${!idx}"
        else
            cmd="$cmd+${!idx}"
        fi
    done
    local pipe=""
    local end=$((${#PIPE[@]} - 1))
    for idx in $(seq 0 $end); do
        if [ "_$pipe" == "_" ]; then
            pipe="$pipe${PIPE[$idx]}"
        else
            pipe="$pipe+${PIPE[$idx]}"
        fi
    done

    if [ "_$DIR" == "" ]; then
        DIR="$(pwd)"
    fi

    if [ "_$STDOUT" == "_" ]; then
        STDOUT="$LOG_FILE"
    fi
    if [ "_$STDERR" == "_" ]; then
        STDERR="$LOG_FILE"
    fi

    if [ $DRY_RUN ]; then
        notify "Execute '$@'"
    elif [ "_$pipe" != "_" ]; then
        local IFS='+'
        while true; do
            notify "Execute '$@'"
            if [ "_$STDOUT" == "_cout" ]; then
                if [ "_$STDERR" == "_cerr" ]; then
                    cd "$DIR" && ($cmd | $pipe) && break || retry || terminate || break
                else
                    cd "$DIR" && ($cmd | $pipe) 2>>$STDERR && break || retry || terminate || break
                fi
            else
                if [ "_$STDERR" == "_cerr" ]; then
                    cd "$DIR" && ($cmd | $pipe) >>$STDOUT && break || retry || terminate || break
                else
                    cd "$DIR" && ($cmd | $pipe) >>$STDOUT 2>>$STDERR && break || retry || terminate || break
                fi
            fi
        done
    else
        local IFS='+'
        while true; do
            notify "Execute '$@'"
            if [ "_$STDOUT" == "_cout" ]; then
                if [ "_$STDERR" == "_cerr" ]; then
                    cd "$DIR" && $cmd && break || retry || terminate || break
                else
                    cd "$DIR" && $cmd 2>>$STDERR && break || retry || terminate || break
                fi
            else
                if [ "_$STDERR" == "_cerr" ]; then
                    cd "$DIR" && $cmd >>$STDOUT && break || retry || terminate || break
                else
                    cd "$DIR" && $cmd >>$STDOUT 2>>$STDERR && break || retry || terminate || break
                fi
            fi
        done
    fi

    unset PIPE
    unset STDOUT
    unset STDERR
}

function run_once {
    local cmd=""
    for idx in $(seq $#); do
        if [ "_$cmd" == "_" ]; then
            cmd="$cmd${!idx}"
        else
            cmd="$cmd+${!idx}"
        fi
    done
    local pipe=""
    local end=$((${#PIPE[@]} - 1))
    for idx in $(seq 0 $end); do
        if [ "_$pipe" == "_" ]; then
            pipe="$pipe${PIPE[$idx]}"
        else
            pipe="$pipe+${PIPE[$idx]}"
        fi
    done

    if [ "_$DIR" == "" ]; then
        DIR="$(pwd)"
    fi

    if [ "_$STDOUT" == "_" ]; then
        STDOUT="$LOG_FILE"
    fi
    if [ "_$STDERR" == "_" ]; then
        STDERR="$LOG_FILE"
    fi

    if [ $DRY_RUN ]; then
        notify "Execute '$@'"
    elif [ "_$pipe" != "_" ]; then
        notify "Execute '$@'"
        if [ "_$STDOUT" == "_cout" ]; then
            if [ "_$STDERR" == "_cerr" ]; then
                cd "$DIR" && ($cmd | $pipe)
            else
                cd "$DIR" && ($cmd | $pipe) 2>>$STDERR
            fi
        else
            if [ "_$STDERR" == "_cerr" ]; then
                cd "$DIR" && ($cmd | $pipe) >>$STDOUT
            else
                cd "$DIR" && ($cmd | $pipe) >>$STDOUT 2>>$STDERR
            fi
        fi
    else
        local IFS='+'
        notify "Execute '$@'"
        if [ "_$STDOUT" == "_cout" ]; then
            if [ "_$STDERR" == "_cerr" ]; then
                cd "$DIR" && $cmd
            else
                cd "$DIR" && $cmd 2>>$STDERR
            fi
        else
            if [ "_$STDERR" == "_cerr" ]; then
                cd "$DIR" && $cmd >>$STDOUT
            else
                cd "$DIR" && $cmd >>$STDOUT 2>>$STDERR
            fi
        fi
    fi

    unset PIPE
    unset STDOUT
    unset STDERR
}

# Install neovim LSP
NEOVIM=1
function nvim_install_lsp {
    if [ $NEOVIM ]; then
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
            warn "Environment '\$http_proxy' is empty!"
        else
            info "Environment '\$http_proxy' is '$http_proxy'"
        fi
        if [ "_$https_proxy" == "_" ]; then
            missing=0
            warn "Environment '\$https_proxy' is empty!"
        else
            info "Environment '\$https_proxy' is '$https_proxy'"
        fi
        if [ $missing ]; then
            warn "Fill missing proxy environment variables."
            exit 0
        fi
    fi
}

# Check for sudo
function check_sudo {
    info "Check for sudo privileges.."
    sudo echo -n "" || exit
}

# Initialize log
touch $LOG_FILE
info "Logging into ${LOG_FILE}."
