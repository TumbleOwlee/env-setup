#!/bin/bash

# Include helpers
source <(curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/common.sh" 2>/dev/null) || exit

# Cache sudo privileges
check_sudo

# Ask for proxy
check_proxy

# Update and upgrade
info "Update and upgrade."
run_with_retry sudo apt update
run_with_retry sudo apt upgrade -y

# Install requirements
info "Install requirements."
run_with_retry sudo apt install -y git python3 pipx unzip

# Install alacritty
resp=$(ask "Install alacritty? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install alacritty"
    run_with_retry sudo add-apt-repository ppa:aslatter/ppa -y
    run_with_retry sudo apt update
    run_with_retry sudo apt install -y alacritty

    # Create alacritty configuration
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "/home/$USER/.config/alacritty"
    run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/alacritty/alacritty.yml" \
        -o "/home/$USER/.config/alacritty/alacritty.yml"
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
        run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/fish/$sc.fish" \
            -o "/home/$USER/.config/fish/functions/$sc.fish"
    done
fi

# Install tmux
resp=$(ask "Install tmux? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install tmux"
    run_with_retry sudo apt install -y tmux

    # Create tmux configuration
    run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/tmux/tmux.conf" \
        -o "/home/$USER/.tmux.conf"
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
        DIR="/home/$USER/.local/share/nvim/site/pack/packer/start/packer.nvim/" run_with_retry git pull
    else
        run_with_retry git clone https://github.com/wbthomason/packer.nvim "/home/$USER/.local/share/nvim/site/pack/packer/start/packer.nvim"
    fi
    run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/neovim-config/main/init.lua" \
        -o "/home/$USER/.config/nvim/init.lua"
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
    PIPE=(bash -s -- -y) && run_with_retry curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs

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
