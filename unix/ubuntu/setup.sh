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

# Install neovim LSP
NEOVIM=1
function nvim_install_lsp {
    if [ $NEOVIM ]; then
        while true; do
            notify "Install neovim $1 LSP support"
            nvim --headless -c "MasonInstall $1" -c "quitall" >>$LOG_FILE 2>&1 && break || retry || terminate || break
        done
    fi
}

# Cache sudo privileges
info "Check for sudo privileges.."
sudo echo -n "" || exit

# Ask for proxy
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

# Initialize log
touch $LOG_FILE
info "Logging into ${LOG_FILE}."

# Update and upgrade
info "Update and upgrade."
while true; do
    notify "Execute 'apt update'.."
    sudo apt update >>$LOG_FILE 2>&1 && break || retry || terminate || break
done
while true; do
    notify "Execute 'apt upgrade'.."
    sudo apt upgrade -y >>$LOG_FILE 2>&1 && break || retry || terminate || break
done

# Install requirements
info "Install requirements."
while true; do
    notify "Execute 'apt install'.."
    sudo apt install -y git curl python3 pipx unzip >>$LOG_FILE 2>&1 && break || retry || terminate || break
done

# Install alacritty
resp=$(ask "Install alacritty? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install alacritty"
    while true; do
        notify "Add 'ppa:aslatter/ppa'.."
        sudo add-apt-repository ppa:aslatter/ppa -y >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    while true; do
        notify "Execute 'apt update'.."
        sudo apt update >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    while true; do
        notify "Execute 'apt install'.."
        sudo apt install -y alacritty >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    # Create alacritty configuration
    while true; do
        notify "Create 'alacritty.yml'"
        mkdir -p ~/.config/alacritty >/dev/null 2>&1 && \
            curl https://raw.githubusercontent.com/TumbleOwlee/setup_env/main/unix/configs/alacritty/alacritty.yml > ~/.config/alacritty/alacritty.yml 2>/dev/null && \
            break || retry || terminate || break
    done
fi

# Install fish
resp=$(ask "Install fish shell? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install fish shell"
    while true; do
        notify "Execute 'apt install'.."
        sudo apt install -y fish >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    while true; do
        notify "Set 'fish' as default shell."
        sudo chsh -s $(which fish) >>$LOG_FILE 2>&1 && sudo usermod -s /usr/bin/fish $(whoami) >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    # Create fish configuration
    scripts=('fish_greeting' 'fish_prompt')
    for sc in ${scripts[@]}; do
        while true; do
            mkdir -p ~/.config/fish/functions >/dev/null 2>&1
            notify "Create '$sc.fish'"
            curl https://raw.githubusercontent.com/TumbleOwlee/setup_env/main/unix/configs/fish/$sc.fish > ~/.config/fish/functions/$sc.fish 2>/dev/null && \
                break || retry || terminate || break
        done
    done
fi

# Install tmux
resp=$(ask "Install tmux? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install tmux"
    while true; do
        notify "Execute 'apt install'.."
        sudo apt install -y tmux >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    # Create tmux configuration
    while true; do
        notify "Create '.tmux.conf'"
        curl https://raw.githubusercontent.com/TumbleOwlee/setup_env/main/unix/configs/tmux/tmux.conf > ~/.tmux.conf 2>/dev/null && \
            break || retry || terminate || break
    done
fi

# Install neovim
resp=$(ask "Install neovim? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install neovim"
    while true; do
        notify "Add 'neovim-ppa/unstable'."
        sudo add-apt-repository ppa:neovim-ppa/unstable -y >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    while true; do
        notify "Execute 'apt update'.."
        sudo apt update >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    while true; do
        notify "Execute 'apt install'.."
        sudo apt install -y neovim >>$LOG_FILE 2>&1 && NEOVIM=0 && break || retry || terminate || break
    done

    # Get neovim configuration
    while true; do
        notify "Install packer."
        mkdir -p ~/.config/nvim >/dev/null 2>&1
        git clone https://github.com/wbthomason/packer.nvim ~/.local/share/nvim/site/pack/packer/start/packer.nvim >>$LOG_FILE 2>&1 || (cd ~/.local/share/nvim/site/pack/packer/start/packer.nvim && git pull >>$LOG_FILE 2>&1) && \
             break || retry || terminate || break
    done
    while true; do
        notify "Create 'init.lua'."
        mkdir -p ~/.config/nvim >/dev/null 2>&1
        curl https://raw.githubusercontent.com/TumbleOwlee/neovim-config/main/init.lua > ~/.config/nvim/init.lua 2>>$LOG_FILE && \
            break || retry || terminate || break
    done

    # Install neovim plugins
    while true; do
        notify "Install neovim plugins.."
        nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerInstall' >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
fi

# Install docker
resp=$(ask "Install docker? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install docker"
    while true; do
        notify "Execute 'apt install'"
        sudo apt install -y docker docker-compose >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    while true; do
        notify "Enable and start docker service"
        sudo systemctl enable --now docker >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    while true; do
        notify "Add user to docker group."
        sudo groupadd docker >>$LOG_FILE 2>&1
        sudo usermod -aG docker $USER >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
fi

# Install rust environment
resp=$(ask "Install rust environment? [y/N]" "N")
if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
    info "Install rustup"
    while true; do
        notify "Execute 'curl https://sh.rustup.rs | bash'.."
        (curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y) >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    # Install toolchain
    while [ -f "$HOME/.cargo/env" ]; do
        source "$HOME/.cargo/env"
        notify "Install toolchain.."
        rustup toolchain install stable >>$LOG_FILE 2>&1 && \
            rustup default stable >>$LOG_FILE 2>&1 && \
            rustup component add rust-src rust-analyzer >>$LOG_FILE 2>&1 && \
            break || retry || terminate || break
    done

    # Install nvim lsp
    nvim_install_lsp "rust-analyzer"
fi

# Install C++ environment
resp=$(ask "Install C++ environment? [y/N]" "N")
if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
    info "Install clang, clang-format, gcc, cmake"
    while true; do
        notify "Execute 'apt install'.."
        sudo apt install -y clang clang-format gcc cmake >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    # Install nvim lsp
    nvim_install_lsp "clangd"

    resp=$(ask "Install Conan? [y/N]" "N")
    if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
        while true; do
            notify "Execute 'pipx install'.."
            pipx install conan >>$LOG_FILE 2>&1 && warn "Make sure '~/.local/bin' is in \$PATH" && break || retry || terminate || break
        done
    fi
fi
