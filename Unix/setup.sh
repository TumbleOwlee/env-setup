#!/bin/bash

NONE="\e[0m"
YELLOW="\e[33m"

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

if ! type "curl" >/dev/null; then
    if is_arch; then
        if type "yay" 2>/dev/null >/dev/null; then
            yay -S --noconfirm curl
        else
            pacman -S --noconfirm curl
        fi
    elif is_ubuntu; then
        $SUDO apt-get install -y curl
    else
        echo "Unsupported operating system." 1>&2
        exit 1
    fi
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

if is_arch; then
    if [ "_$DEBUG" == "_" ]; then
        source <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Arch/setup.sh 2>/dev/null) $@
    else
        echo -e "[${YELLOW}?${NONE}] Debug mode active." 1>&2
        source "$SCRIPT_DIR/Arch/setup.sh"
    fi
elif is_ubuntu; then
    if [ "_$DEBUG" == "_" ]; then
        source <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Ubuntu/setup.sh 2>/dev/null) $@
    else
        echo -e "[${YELLOW}?${NONE}] Debug mode active." 1>&2
        source "$SCRIPT_DIR/Ubuntu/setup.sh"
    fi
fi
