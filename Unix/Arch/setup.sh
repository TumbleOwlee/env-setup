#!/bin/bash

# Include helpers
source <(curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/common.sh" 2>/dev/null) || exit

# Cache sudo privileges
check_sudo

# Ask for proxy
check_proxy

# Update and upgrade
info "Update and upgrade."
run_with_retry yay -Syyu --noconfirm

# Install requirements
info "Install requirements."
run_with_retry yay -S --noconfirm git python python-pipx

# Install alacritty
resp=$(ask "Install alacritty? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install alacritty"
    run_with_retry yay -S --noconfirm alacritty

    # Create alacritty configuration
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config/alacritty"
    run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/alacritty/alacritty.yml" \
        -o "$HOME/.config/alacritty/alacritty.yml"
fi

# Install fish
resp=$(ask "Install fish shell? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install fish shell"
    run_with_retry yay -S --noconfirm fish
    run_with_retry sudo chsh -s $(which fish)
    run_with_retry sudo usermod -s /usr/bin/fish $(whoami)

    # Create fish configuration
    scripts=('fish_greeting' 'fish_prompt')
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config/fish/functions"
    for sc in ${scripts[@]}; do
        run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/fish/$sc.fish" \
            -o "$HOME/.config/fish/functions/$sc.fish"
    done

    if [ -f "$HOME/.config/alacritty/alacritty.yml" ]; then
        echo -e "shell:\n  program: /usr/bin/fish\n  args:\n    - -c\n    - tmux" >> "$HOME/.config/alacritty/alacritty.yml"
    fi
fi

# Install tmux
resp=$(ask "Install tmux? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install tmux"
    run_with_retry yay -S --noconfirm tmux

    # Create tmux configuration
    run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/tmux/tmux.conf" \
        -o "$HOME/.tmux.conf"

    if [ -d "$HOME/.config/fish" ]; then
        echo "set -g default-shell $(which fish)" >> "$HOME/.tmux.conf"
    fi
fi

# Install neovim
resp=$(ask "Install neovim? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install neovim"
    run_with_retry yay -S --noconfirm neovim
 
    # Install NerdFont
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir /tmp/
    run_with_retry wget -P /tmp/ https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/FiraCode.zip
    STDERR="&2" run_with_retry unzip /tmp/FiraCode.zip -x README.md LICENSE -d ~/.fonts
    if [ -x "$(command -v fc-cache)" ]; then
        STDOUT=/dev/null STDERR=/dev/null run_once fc-cache -fv
    else
        warn "fc-cache NOT found. Font files installed but font cache NOT updated."
    fi

    # Get neovim configuration
    info "Install packer"
    if [ -d "$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim/.git" ]; then
        DIR="$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim/" run_with_retry git pull
    else
        run_with_retry git clone https://github.com/wbthomason/packer.nvim "$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"
    fi

    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config/nvim"
    run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/neovim-config/main/init.lua" \
        -o "$HOME/.config/nvim/init.lua"
    # Install neovim plugins
    run_with_retry nvim --headless -c "autocmd User PackerComplete quitall" -c "PackerInstall"
fi

# Install docker
resp=$(ask "Install docker? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install docker"
    run_with_retry yay -S --noconfirm docker docker-compose
    run_with_retry sudo systemctl enable --now docker
    run_once sudo groupadd docker
    run_with_retry sudo usermod -aG docker $USER
fi

# Install rust environment
resp=$(ask "Install rust environment? [y/N]" "N")
if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
    info "Install rustup"
    resp=$(ask "Install bleeding edge? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        pkg="rustup-git"
    else
        pkg="rustup"
    fi
    run_with_retry yay -S --noconfirm $pkg

    # Install toolchain
    run_with_retry rustup toolchain install stable
    run_with_retry rustup default stable
    run_with_retry rustup component add rust-src rust-analyzer

    # Install nvim lsp
    nvim_install_lsp "rust-analyzer"

    if [ -d "$HOME/.config/fish" ]; then
        info "Adding '$HOME/.cargo/bin' to \$PATH"
        fish -c "fish_add_path -a '$HOME/.cargo/bin'"
    else
        warn "Make sure '$HOME/.cargo/bin' is in \$PATH"
    fi
fi

# Install C++ environment
resp=$(ask "Install C++ environment? [y/N]" "N")
if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
    info "Install clang, gcc, cmake"
    run_with_retry yay -S --noconfirm clang gcc cmake

    # Install nvim lsp
    nvim_install_lsp "clangd"

    resp=$(ask "Install Conan? [y/N]" "N")
    if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
        run_with_retry pipx install conan
        if [ -d "$HOME/.config/fish" ]; then
            info "Adding '$HOME/.local/bin' to \$PATH"
            fish -c "fish_add_path -a '$HOME/.local/bin'"
        else
            warn "Make sure '$HOME/.local/bin' is in \$PATH"
        fi
    fi
fi
