#!/bin/bash

function is_arch {
    if type "yay" > /dev/null; then
        true
    else
        false
    fi
}

function is_ubuntu {
    if type "apt" > /dev/null; then
        true
    else
        false
    fi
}


if ! type "curl" > /dev/null; then
    if [ is_arch ]; then
        yay -S --noconfirm curl
    elif [ is_ubuntu ]; then
        sudo apt install -y curl
    else
        echo "Unsupported operating system." 1>&2
        exit 1
    fi
fi

if [ is_arch ]; then
    curl https://raw.githubusercontent.com/TumbleOwlee/setup_env/main/ubuntu/setup.sh | /bin/bash
elif [ is_ubuntu ]; then
    curl https://raw.githubusercontent.com/TumbleOwlee/setup_env/main/arch/setup.sh | /bin/bash
fi
