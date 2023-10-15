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
    echo -e -n "[${RED}?${NONE}] Retry? [Y/n] " 1>&2
    echo -e -n "[?] $1 " >>$LOG_FILE
    read value
    if [ "_$value" == "_n" ] || [ "_$value" == "_N" ]; then
        false
    else
        true
    fi
}

# Ask for termination
function terminate {
    echo -e -n "[${RED}?${NONE}] Terminate? [Y/n] " 1>&2
    echo -e -n "[?] $1 " >>$LOG_FILE
    read value
    if [ "_$value" == "_n" ] || [ "_$value" == "_N" ]; then
        false
    else
        exit 0
    fi
}

# Warn the user
function warn {
    echo -e "[${RED}!${NONE}] $1"
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
    for idx in $(seq ${#PIPE[@]}); do
        if [ "_$pipe" == "_" ]; then
            pipe="$pipe${PIPE[$idx]}"
        else
            pipe="$pipe+${PIPE[$idx]}"
        fi
    done

    if [ $DRY_RUN ]; then
        notify "Execute '$@'"
    elif [ "_$pipe" != "_" ]; then
        local IFS='+'
        while true; do
            notify "Execute piped '$@'"
            $cmd | $pipe && break || retry || terminate || break
        done
    else
        if [ "_$STDOUT" == "_" ]; then
            STDOUT="$LOG_FILE"
        fi
        if [ "_$STDERR" == "_" ]; then
            STDERR="$LOG_FILE"
        fi

        local IFS='+'
        while true; do
            notify "Execute '$@'"
            if [ "_$STDOUT" == "_$STDERR" ]; then
                $cmd >>"$STDOUT" 2>&1 && break || retry || terminate || break
            else
                $cmd >>"$STDOUT" 2>>"$STDERR" && break || retry || terminate || break
            fi
        done
    fi
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
    for idx in $(seq ${#PIPE[@]}); do
        if [ "_$pipe" == "_" ]; then
            pipe="$pipe${PIPE[$idx]}"
        else
            pipe="$pipe+${PIPE[$idx]}"
        fi
    done

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
        if [ "_$STDOUT" == "_$STDERR" ]; then
            $cmd | $pipe >>"$STDOUT" 2>&1
        else
            $cmd | $pipe >>"$STDOUT" 2>>"$STDERR"
        fi
    else
        local IFS='+'
        notify "Execute '$@'"
        if [ "_$STDOUT" == "_$STDERR" ]; then
            $cmd >>"$STDOUT" 2>&1
        else
            $cmd >>"$STDOUT" 2>>"$STDERR"
        fi
    fi
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

# Cache sudo privileges
check_sudo

# Ask for proxy
check_proxy

# Initialize log
touch $LOG_FILE
info "Logging into ${LOG_FILE}."

# Update and upgrade
info "Update and upgrade."
run_with_retry sudo apt update
run_with_retry sudo apt upgrade -y

# Install requirements
info "Install requirements."
run_with_retry sudo apt install -y git curl python3 pipx unzip

# Install alacritty
resp=$(ask "Install alacritty? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install alacritty"
    run_with_retry sudo add-apt-repository ppa:aslatter/ppa -y
    run_with_retry sudo apt update
    run_with_retry sudo apt install -y alacritty

    # Create alacritty configuration
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "/home/$USER/.config/alacritty"
    STDOUT="/home/$USER/.config/alacritty/alacritty.yml" \
        run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/setup_env/main/unix/configs/alacritty/alacritty.yml"
fi

# Install fish
resp=$(ask "Install fish shell? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install fish shell"
    run_with_retry sudo apt install -y fish 
    run_with_retry sudo chsh -s $(which fish)
    run_with_retry sudo usermod -s /usr/bin/fish $(whoami)

    # Create fish configuration
    scripts=('fish_greeting' 'fish_prompt')
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "/home/$USER/.config/fish/functions"
    for sc in ${scripts[@]}; do
        STDOUT="/home/$USER/.config/fish/functions/$sc.fish" \
            run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/setup_env/main/unix/configs/fish/$sc.fish"
    done
fi

# Install tmux
resp=$(ask "Install tmux? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install tmux"
    run_with_retry sudo apt install -y tmux

    # Create tmux configuration
    STDOUT="/home/$USER/.tmux.conf" \
        run_with_retry curl https://raw.githubusercontent.com/TumbleOwlee/setup_env/main/unix/configs/tmux/tmux.conf
fi

# Install neovim
resp=$(ask "Install neovim? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install neovim"
    run_with_retry sudo add-apt-repository ppa:neovim-ppa/unstable -y
    run_with_retry sudo apt update
    run_with_retry sudo apt install -y neovim 
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "/home/$USER/.config/nvim"

    # Get neovim configuration
    info "Install packer"
    if [ -d "/home/$USER/.local/share/nvim/site/pack/packer/start/packer.nvim/.git" ]; then
        run_with_retry git pull
    else
        run_with_retry git clone https://github.com/wbthomason/packer.nvim "/home/$USER/.local/share/nvim/site/pack/packer/start/packer.nvim"
    fi
    STDOUT="/home/$USER/.config/nvim/init.lua" \
        run_with_retry curl https://raw.githubusercontent.com/TumbleOwlee/neovim-config/main/init.lua
    # Install neovim plugins
    run_with_retry nvim --headless -c "autocmd User PackerComplete quitall" -c "PackerInstall"
fi

# Install docker
resp=$(ask "Install docker? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install docker"
    run_with_retry sudo apt install -y docker docker-compose 
    run_with_retry sudo systemctl enable --now docker 
    run_once sudo groupadd docker 
    run_with_retry sudo usermod -aG docker $USER
fi

# Install rust environment
resp=$(ask "Install rust environment? [y/N]" "N")
if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
    info "Install rustup"
    PIPE=(bash -s -- -y) run_with_retry curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs

    # Install toolchain
    run_with_retry source "$HOME/.cargo/env"
    run_with_retry rustup toolchain install stable
    run_with_retry rustup default stable
    run_with_retry rustup component add rust-src rust-analyzer

    # Install nvim lsp
    nvim_install_lsp "rust-analyzer"
fi

# Install C++ environment
resp=$(ask "Install C++ environment? [y/N]" "N")
if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
    info "Install clang, clang-format, gcc, cmake"
    run_with_retry sudo apt install -y clang clang-format gcc cmake

    # Install nvim lsp
    nvim_install_lsp "clangd"

    resp=$(ask "Install Conan? [y/N]" "N")
    if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
        run_with_retry pipx install conan 
        warn "Make sure '/home/$USER/.local/bin' is in \$PATH"
    fi
fi
