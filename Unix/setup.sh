#!/bin/bash

function is_arch {
    if type "yay" 2>/dev/null >/dev/null; then
        return 0
    else
        return 1
    fi
}

function is_ubuntu {
    if type "apt" 2>/dev/null >/dev/null; then
        return 0
    else
        return 1
    fi
}


if ! type "curl" > /dev/null; then
    if is_arch; then
        yay -S --noconfirm curl
    elif is_ubuntu; then
        sudo apt install -y curl
    else
        echo "Unsupported operating system." 1>&2
        exit 1
    fi
fi

if is_arch; then
    bash -c "bash <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Arch/setup.sh)"
elif is_ubuntu; then
    bash -c "bash <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Ubuntu/setup.sh)"
fi
