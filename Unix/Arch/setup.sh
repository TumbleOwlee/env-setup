#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

USER=$(whoami)

for i in "$@"; do
    case $i in
    -d | --debug)
        export DEBUG=y
        ;;
    -n | --noconfirm)
        export NO_CONFIRM="YES"
        ;;
    --skip=*)
        NAME="${i#*=}"
        NAME="$(echo $NAME | tr '[:lower:]' '[:upper:]')"
        export "SKIP_$NAME=YES"
        ;;
    *) ;;
    esac
done

# Include helpers
if [ "_$DEBUG" == "_" ]; then
    source <(curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/common.sh" 2>/dev/null) || exit
else
    source "$SCRIPT_DIR/../common.sh" || exit
fi

# Abort if root
if [ ! -z "$(whoami)" ] && [ "$(whoami)" == "root" ]; then
    warn "Unable to setup environment as root. Please run it as non-root user."
    exit 1
fi

# Cache sudo privileges
check_sudo

# Ask for proxy
check_proxy

# Update and upgrade
resp=$(ask "Update and upgrade? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Update and upgrade."
    if [ -z "$SUDO" ]; then
        run_with_retry pacman -Syyu --noconfirm
    else
        run_with_retry $SUDO pacman -Syyu --noconfirm
    fi
fi

# Install yay
run_with_retry $SUDO pacman -S --needed --noconfirm git base-devel less

tmpdir=$(mktemp -d)
run_with_retry git clone https://aur.archlinux.org/yay-bin.git $tmpdir/yay-bin
DIR=$tmpdir/yay-bin STDOUT=/dev/null STDERR=/dev/null run_with_retry makepkg -s
STDOUT=/dev/null STDERR=/dev/null run_once rm $tmpdir/yay-bin/yay-bin-debug*.pkg.tar.zst
run_with_retry $SUDO pacman -U --noconfirm $tmpdir/yay-bin/yay-bin-*.pkg.tar.zst
rm -rf $tmpdir

# Install requirements
info "Install requirements."
run_with_retry yay -S --noconfirm git python python-pipx unzip wget zoxide wget less

# Add .local/bin to PATH
cat $HOME/.bashrc 2>/dev/null | grep -q 'export PATH=$PATH:~/.local/bin' || echo 'export PATH=$PATH:~/.local/bin' >>$HOME/.bashrc
export PATH="$PATH:~/.local/bin"

# Init zoxide for bash
cat $HOME/.bashrc 2>/dev/null | grep -q 'ZOXIDE INIT' || echo '
# ZOXIDE INIT
zoxide init --cmd cd bash | source' >>$HOME/.bashrc
. "$HOME/.bashrc"

# Update BSPWM
if [ -d "$HOME/.config/bspwm" ]; then
    info "Update config of BSPWM"
    run_with_retry sed -i "s/bspc.*config.*window_gap.*/bspc config window_gap 2/g" "$HOME/.config/bspwm/bspwmrc"
    run_with_retry sed -i "s/bspc.*config.*border_width.*/bspc config border_width 1/g" "$HOME/.config/bspwm/bspwmrc"
fi

# Install fish
if [ -z "$SKIP_FISH" ]; then
    resp=$(ask "Install fish shell? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install fish shell"
        run_with_retry yay -S --noconfirm fish
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
            notify "Adding '${CYAN}$HOME/.local/bin${NONE}' to ${CYAN}\$PATH${NONE}"
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

        cat $HOME/.config/fish/config.fish 2>/dev/null | grep -q 'CAT ALIAS' || echo '
# CAT ALIAS
alias ccat=(which cat 2>/dev/null)
alias cat=colored_cat' >>$HOME/.config/fish/config.fish

        if [ ! -z "$(which zoxide 2>/dev/null)" ]; then
            cat $HOME/.config/fish/config.fish 2>/dev/null | grep -q 'ZOXIDE INIT' || echo '
# ZOXIDE INIT
zoxide init --cmd cd fish | source' >>$HOME/.config/fish/config.fish
        fi
    fi
fi

# Install tmux
if [ -z "$SKIP_TMUX" ]; then
    resp=$(ask "Install tmux? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install tmux"
        run_with_retry yay -S --noconfirm tmux

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
fi

# Install neovim
if [ -z "$SKIP_NEOVIM" ]; then
    resp=$(ask "Install neovim? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install neovim"
        run_with_retry yay -S --noconfirm ninja-build neovim-git

        # Install NerdFont
        tmpdir=$(mktemp -d)
        run_with_retry wget -P $tmpdir/ https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip
        run_with_retry unzip -o $tmpdir/FiraCode.zip -x README.md LICENSE -d ~/.fonts
        rm -rf $tmpdir
        if [ ! -x "$(command -v fc-cache)" ]; then
            info "Install missing fontconfig"
            run_with_retry yay -S --noconfirm fontconfig
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
fi

# Install docker
if [ -z "$SKIP_DOCKER" ]; then
    resp=$(ask "Install docker? [Y/n]" "Y")
    if [ -z "$IS_VM" ] && [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install docker"
        run_with_retry yay -S --noconfirm docker docker-compose
        run_with_retry $SUDO systemctl enable --now docker
        run_once $SUDO groupadd docker
        run_with_retry $SUDO usermod -aG docker $USER
    fi
fi

REQUIRE_RUST=0
if [ -z "$SKIP_ALACRITTY" ]; then
    # Install alacritty
    resp_alacritty=$(ask "Install alacritty? [Y/n]" "Y")
    if [ "_$resp_alacritty" != "_n" ] && [ "_$resp_alacritty" != "_N" ]; then
        REQUIRE_RUST=1
    fi
fi

# Install rust environment
if [ $REQUIRE_RUST -eq 1 ] || [ -z "$SKIP_RUST" ]; then
    if [ $REQUIRE_RUST -ne 1 ]; then
        resp=$(ask "Install rust environment? [Y/n]" "Y")
    else
        resp="Y"
    fi
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install rustup"
        resp=$(ask "Install bleeding edge? [y/N]" "N")
        if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
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
            notify "Adding '${CYAN}$HOME/.cargo/bin${NONE}' to ${CYAN}\$PATH${NONE}"
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

        run_with_retry cargo install cross --git https://github.com/cross-rs/cross
    fi
fi

# Install alacritty
if [ -z "$SKIP_ALACRITTY" ]; then
    # Install alacritty
    if [ "_$resp_alacritty" != "_n" ] && [ "_$resp_alacritty" != "_N" ]; then
        info "Install alacritty"
        run_with_retry yay -S --noconfirm alacritty-git

        if [ -f "$HOME/.config/alacritty/alacritty.yml" ]; then
            warn "Deprecated alacritty.yml file found. Move to '$HOME/.config/alacritty/old.alacritty.yml'"
            STDOUT=/dev/null STDERR=/dev/null run_once mv "$HOME/.config/alacritty/alacritty.yml" "$HOME/.config/alacritty/alacritty.toml"
        fi

        # Create alacritty configuration
        STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config/alacritty"
        if [ "_$DEBUG" == "_" ]; then
            run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/alacritty/alacritty.toml" \
                -o "$HOME/.config/alacritty/alacritty.toml"
        else
            run_with_retry cp "$SCRIPT_DIR/../Configs/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"
        fi
    fi

    # Install utility scripts
    resp=$(ask "Install utility scripts? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        scripts=('Scripts/git-cmd/git-sync' 'Scripts/git-cmd/git-check' 'Scripts/git-cmd/git-hooks' 'Scripts/custom/dbg' 'Scripts/custom/docker-run' 'Scripts/custom/finance' 'Scripts/bspwm/win-move')
        STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.local/bin"
        for sc in ${scripts[@]}; do
            if [ "_$DEBUG" == "_" ]; then
                base="$(basename $sc)"
                run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/$sc" \
                    -o "$HOME/.local/bin/$base"
                chmod +x "$HOME/.local/bin/$base"
            else
                run_with_retry cp "$SCRIPT_DIR/../$sc" "$HOME/.local/bin/"
            fi
        done
    fi
fi

# Install C++ environment
if [ -z "$SKIP_CXX" ]; then
    resp=$(ask "Install C++ environment? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install clang, gcc, cmake"
        run_with_retry yay -S --noconfirm clang gcc cmake

        # Install nvim lsp
        nvim_install_lsp "clangd"

        resp=$(ask "Install Conan? [Y/n]" "Y")
        if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
            run_with_retry pipx install conan
        fi
    fi
fi

if [ -z "$SKIP_DELTA" ]; then
    resp=$(ask "Install delta? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install delta using yay"
        run_with_retry yay -S --noconfirm git-delta

        STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config/delta"
        STDOUT=/dev/null STDERR=/dev/null run_with_retry curl https://raw.githubusercontent.com/dandavison/delta/main/themes.gitconfig -o "$HOME/.config/delta/themes.gitconfig"

        STDOUT=/dev/null STDERR=/dev/null run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/git/gitconfig" \
            -o "$HOME/.gitconfig.new"

        if [ -f "$HOME/.gitconfig.new" ]; then
            cat "$HOME/.gitconfig.new" >>"$HOME/.gitconfig" 2>/dev/null
            rm "$HOME/.gitconfig.new"
        fi
    fi
fi

if [ -z "$SKIP_ALACRITTY" ]; then
    if [ -f "$HOME/.config/alacritty" ]; then
        warn "If alacritty doesn't show rendered font, try using this: alacritty -o 'debug.renderer=\"gles2\"'"
    fi
fi

delete_log
