#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# Include helpers
if [ "_$DEBUG" == "_" ]; then
    source <(curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/common.sh" 2>/dev/null) || exit
else
    source "$SCRIPT_DIR/../common.sh" || exit
fi

# Cache sudo privileges
check_sudo

# Ask for proxy
check_proxy

# Update and upgrade
info "Update and upgrade."
run_with_retry $SUDO apt-get update
run_with_retry $SUDO apt-get upgrade -y

# Install requirements
info "Install requirements."
run_with_retry $SUDO apt-get install -y git python3 pipx unzip software-properties-common wget python3-venv

info "Install zoxide."
mkdir -p "$HOME/.cache" &>/dev/null
run_with_retry curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh -o "$HOME/.cache/zoxide_install.sh"
run_with_retry bash "$HOME/.cache/zoxide_install.sh"
rm "$HOME/.cache/zoxide_install.sh" &>/dev/null

# Add .local/bin to PATH
cat $HOME/.bashrc 2>/dev/null | grep -q 'export PATH=$PATH:~/.local/bin' || echo 'export PATH=$PATH:~/.local/bin' >>$HOME/.bashrc
export PATH="$PATH:~/.local/bin"

# Init zoxide for bash
echo "# Init zoxide" >>$HOME/.bashrc
zoxide init bash >>$HOME/.bashrc
. "$HOME/.bashrc"

# Update BSPWM
if [ -d "$HOME/.config/bspwm" ]; then
    info "Update config of BSPWM"
    run_with_retry sed -i "s/bspc.*config.*window_gap.*/bspc config window_gap 2/g" "$HOME/.config/bspwm/bspwmrc"
    run_with_retry sed -i "s/bspc.*config.*border_width.*/bspc config border_width 1/g" "$HOME/.config/bspwm/bspwmrc"
fi

# Install alacritty
resp=$(ask "Install alacritty? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install alacritty"
    run_with_retry $SUDO add-apt-repository ppa:aslatter/ppa -y
    run_with_retry $SUDO apt-get update
    run_with_retry $SUDO apt-get install -y alacritty

    # Create alacritty configuration
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config/alacritty"
    if [ "_$DEBUG" == "_" ]; then
        run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/alacritty/alacritty.toml" \
            -o "$HOME/.config/alacritty/alacritty.toml"
    else
        run_with_retry cp "$SCRIPT_DIR/../Configs/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"
    fi
fi

# Install fish
resp=$(ask "Install fish shell? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install fish shell"
    run_with_retry $SUDO apt-get install -y fish
    run_with_retry $SUDO chsh -s $(which fish)
    run_with_retry $SUDO usermod -s /usr/bin/fish $(whoami)

    # Create fish configuration
    scripts=('fish_greeting' 'fish_prompt' 'colored_cat')
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config/fish/functions"
    for sc in ${scripts[@]}; do
        if [ "_$DEBUG" == "_" ]; then
            run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/fish/$sc.fish" \
                -o "$HOME/.config/fish/functions/$sc.fish"
        else
            run_with_retry cp "$SCRIPT_DIR/../Configs/fish/$sc.fish" "$HOME/.config/fish/functions/$sc.fish"
        fi
    done

    mkdir -p $HOME/.config/fish/conf.d &>/dev/null

    if [ -f "$HOME/.config/alacritty/alacritty.yml" ]; then
        echo -e "shell:\n  program: /usr/bin/fish\n  args:\n    - -c\n    - tmux" >>"$HOME/.config/alacritty/alacritty.yml"
    fi

    export FISH_VERSION=$(fish --version | cut -f3- -d' ' | cut -f1 -d'.')

    if [ -d "$HOME/.config/fish" ]; then
        info "Adding '$HOME/.local/bin' to \$PATH"
        if [ ! -z $FISH_VERSION ]; then
            if [ $FISH_VERSION -gt 3 ]; then
                fish -c 'contains ~/.local/bin $PATH' || fish -c "fish_add_path -a '$HOME/.local/bin'"
            else
                cat $HOME/.config/fish/config.fish 2>/dev/null | grep -q 'LOCAL BIN' || echo '
                    # LOCAL BIN
                    contains ~/.local/bin $PATH
                    or set PATH ~/.local/bin $PATH' >>$HOME/.config/fish/config.fish
            fi
        fi
    fi

    echo "alias ccat=(which cat)" >>$HOME/.config/fish/config.fish
    echo "alias cat=colored_cat" >>$HOME/.config/fish/config.fish

    if [ ! -z "$(which zoxide)" ]; then
        echo "zoxide init fish | source" >>$HOME/.config/fish/config.fish
    fi
fi

# Install tmux
resp=$(ask "Install tmux? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install tmux"
    run_with_retry $SUDO apt-get install -y tmux

    # Create tmux configuration
    if [ "_$DEBUG" == "_" ]; then
        run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/tmux/tmux.conf" \
            -o "$HOME/.tmux.conf"
    else
        run_with_retry cp "$SCRIPT_DIR/../Configs/tmux/tmux.conf" "$HOME/.tmux.conf"
    fi

    if [ -d "$HOME/.config/fish" ]; then
        echo "set -g default-shell $(which fish)" >>"$HOME/.tmux.conf"
    fi
fi

# Install neovim
resp=$(ask "Install neovim? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install neovim"
    run_with_retry $SUDO add-apt-repository ppa:neovim-ppa/unstable -y
    run_with_retry $SUDO apt-get update
    run_with_retry $SUDO apt-get install -y neovim

    # Install NerdFont
    STDOUT=/dev/null STDERR=/dev/null run_once mkdir /tmp/
    run_with_retry wget -P /tmp/ https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip
    STDERR="cerr" run_with_retry unzip /tmp/FiraCode.zip -x README.md LICENSE -d ~/.fonts
    if [ ! -x "$(command -v fc-cache)" ]; then
        info "Install missing fontconfig"
        run_with_retry $SUDO apt-get install -y fontconfig
    fi
    STDOUT=/dev/null STDERR=/dev/null run_once fc-cache -fv

    info "Install/update nvim configuration"
    if [ -d "$HOME/.config/nvim" ]; then
        if [ -d "$HOME/.config/nvim/.git" ]; then
            (cd "$HOME/.config/nvim" && run_with_retry git pull)
        else
            resp=$(ask "Replace existing nvim configuration [Y/n]" "Y")
            if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
                STDOUT=/dev/null STDERR=/dev/null run_once rm -rf "$HOME/.config/nvim"
                run_with_retry git clone "https://github.com/TumbleOwlee/neovim-config" "$HOME/.config/nvim/"
            else
                info "Skip installing nvim configuration"
            fi
        fi
    else
        STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config"
        run_with_retry git clone "https://github.com/TumbleOwlee/neovim-config" "$HOME/.config/nvim/"
    fi

    if [ -d "$HOME/.config/fish" ]; then
        run_with_retry fish -c "alias -s vim=nvim"
        run_with_retry fish -c "alias -s vi=nvim"
        run_with_retry fish -c "alias -s v=nvim"
    fi

    run_with_retry nvim --headless -c 'SyncInstall' -c qall

    # Install nvim lsp
    nvim_install_lsp "lua-language-server"
    nvim_install_lsp "python-lsp-server"
fi

# Install docker
resp=$(ask "Install docker? [Y/n]" "Y")
if [ -z "$IS_VM" ] && [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install docker"
    run_with_retry $SUDO apt-get install -y docker docker-compose docker-buildx
    run_with_retry $SUDO systemctl enable --now docker
    run_once $SUDO groupadd docker
    run_with_retry $SUDO usermod -aG docker $USER
fi

# Install rust environment
resp=$(ask "Install rust environment? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install rustup"

    if [ -d "$HOME/.config/fish" ]; then
        mkdir -p "$HOME/.config/fish/conf.d" &>/dev/null
    fi

    PIPE=(bash -s -- -y) && run_with_retry curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs

    # Install toolchain
    run_with_retry source "$HOME/.cargo/env"
    run_with_retry rustup toolchain install stable
    run_with_retry rustup default stable
    run_with_retry rustup component add rust-src rust-analyzer

    # Install nvim lsp
    nvim_install_lsp "rust-analyzer"

    if [ -d "$HOME/.config/fish" ]; then
        info "Adding '$HOME/.cargo/bin' to \$PATH"
        if [ ! -z $FISH_VERSION ]; then
            if [ $FISH_VERSION -gt 3 ]; then
                fish -c 'contains ~/.cargo/bin $PATH' || fish -c "fish_add_path -a '$HOME/.cargo/bin'"
            else
                cat $HOME/.config/fish/config.fish 2>/dev/null | grep -q 'CARGO BIN' || echo '
                    # CARGO BIN
                    contains ~/.cargo/bin $PATH
                    or set PATH ~/.cargo/bin $PATH' >>$HOME/.config/fish/config.fish
            fi
        fi
    fi

    cat $HOME/.bashrc 2>/dev/null | grep -q 'export PATH=$PATH:~/.cargo/bin' || echo 'export PATH=$PATH:~/.cargo/bin' >>$HOME/.bashrc
    export PATH=$PATH:~/.cargo/bin
fi

# Install C++ environment
resp=$(ask "Install C++ environment? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install clang, clang-format, gcc, cmake"
    run_with_retry $SUDO apt-get install -y clang clang-format gcc cmake

    # Install nvim lsp
    nvim_install_lsp "clangd"

    resp=$(ask "Install Conan? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        run_with_retry pipx install conan
    fi
fi

resp=$(ask "Install delta? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    if [ ! -z "$(which cargo)" ]; then
        info "Install delta using cargo"
        STDOUT=/dev/null STDERR=/dev/null run_with_retry cargo install git-delta
    else
        info "Install delta using github release"
        release=$(curl --silent -m 10 --connect-timeout 5 "https://api.github.com/repos/dandavison/delta/releases/latest")
        tag=$(echo "$release" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        STDOUT=/dev/null STDERR=/dev/null run_with_retry wget --quiet -P "/tmp/" "https://github.com/dandavison/delta/releases/download/$tag/delta-$tag-x86_64-unknown-linux-gnu.tar.gz"
        STDOUT=/dev/null STDERR=/dev/null run_with_retry dpkg -i "/tmp/delta-$tag-x86_64-unknown-linux-gnu.tar.gz"
    fi

    STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config/delta"
    STDOUT=/dev/null STDERR=/dev/null run_with_retry curl https://raw.githubusercontent.com/dandavison/delta/main/themes.gitconfig -o "$HOME/.config/delta/themes.gitconfig"

    STDOUT=/dev/null STDERR=/dev/null run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/git/gitconfig" \
        -o "$HOME/.gitconfig.new"

    if [ -f "$HOME/.gitconfig.new" ]; then
        cat "$HOME/.gitconfig.new" >>"$HOME/.gitconfig" 2>/dev/null
        rm "$HOME/.gitconfig.new"
    fi
fi

if [ -f "$HOME/.config/alacritty" ]; then
    warn "If alacritty doesn't show rendered font, try using this: alacritty -o 'debug.renderer=\"gles2\"'"
fi
