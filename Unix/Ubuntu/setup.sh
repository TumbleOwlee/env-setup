#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

USER=$(whoami)

JOBS=1
NPROC=$(nproc)
if [ ! -z "$NPROC" ]; then
    if [ $NPROC -gt 2 ]; then
        JOBS=$(($NPROC - 1))
    fi
fi

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
run_with_retry $SUDO apt-get install -y git python3 pipx unzip less wget python3-venv gpg curl which fzf

$SUDO apt-get install -y software-properties-common &>/dev/null

info "Install zoxide."
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh 2>/dev/null | sh &>/dev/null

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

# Install fish
if [ -z "$SKIP_FISH" ]; then
    resp=$(ask "Install fish shell? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install fish shell"
        run_with_retry $SUDO apt-get install -y fish
        run_with_retry $SUDO chsh -s $(which fish 2>/dev/null)
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
        run_with_retry $SUDO apt-get install -y tmux

        # Create tmux configuration
        if [ "_$DEBUG" == "_" ]; then
            run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/tmux/tmux.conf" \
                -o "$HOME/.tmux.conf"
        else
            run_with_retry cp "$SCRIPT_DIR/../Configs/tmux/tmux.conf" "$HOME/.tmux.conf"
        fi

        if [ -d "$HOME/.config/fish" ]; then
            echo "set -g default-shell $(which fish 2>/dev/null)" >>"$HOME/.tmux.conf"
        fi
    fi
fi

# Install neovim
if [ -z "$SKIP_NEOVIM" ]; then
    resp=$(ask "Install neovim? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install neovim"

        run_with_retry $SUDO apt-get install -y build-essential cmake ninja-build

        RANDOM_DIR="$(mktemp -d)"
        run_with_retry git clone --depth=1 https://github.com/neovim/neovim $RANDOM_DIR
        DIR=$RANDOM_DIR run_with_retry make -j$JOBS CMAKE_BUILD_TYPE=RelWithDebInfo
        DIR=$RANDOM_DIR run_with_retry $SUDO make -j$JOBS install
        sudo rm -rf $RANDOM_DIR &>/dev/null

        # Install NerdFont
        tmpdir=$(mktemp -d)
        run_with_retry wget -P $tmpdir https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip
        run_with_retry unzip -o $tmpdir/FiraCode.zip -x README.md LICENSE -d ~/.fonts
        rm -r $tmpdir
        if [ ! -x "$(command -v fc-cache)" ]; then
            info "Install missing fontconfig"
            run_with_retry $SUDO apt-get install -y fontconfig
        fi
        STDOUT=/dev/null STDERR=/dev/null run_once fc-cache -fv

        info "Install/update nvim configuration"
        if [ -d "$HOME/.config/nvim" ]; then
            if [ -d "$HOME/.config/nvim/.git" ]; then
                DIR="$HOME/.config/nvim" run_with_retry git pull
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

        run_once nvim --headless -c 'SyncInstall' -c qall
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
        $SUDO apt-cache search '^docker$' | cut -f1 -d' ' | grep -e '^docker$' &>/dev/null
        if [ $? -eq 0 ]; then
            run_with_retry $SUDO apt-get install -y docker docker-compose docker-buildx
        else
            run_with_retry $SUDO apt-get install -y docker.io docker-compose docker-buildx
        fi
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

        if [ -d "$HOME/.config/fish" ]; then
            mkdir -p "$HOME/.config/fish/conf.d" &>/dev/null
        fi

        PIPE=(bash -s -- -y) && run_with_retry curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs

        # Install toolchain
        run_with_retry source "$HOME/.cargo/env"
        export PATH="$PATH:$HOME/.cargo/bin"
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

if [ -z "$SKIP_ALACRITTY" ]; then
    # Install alacritty
    if [ "_$resp_alacritty" != "_n" ] && [ "_$resp_alacritty" != "_N" ]; then
        info "Install alacritty"

        run_with_retry $SUDO apt-get install -y cmake g++ pkg-config libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev python3

        RANDOM_DIR="$(mktemp -d)"
        run_with_retry git clone --depth=1 https://github.com/alacritty/alacritty.git $RANDOM_DIR
        DIR=$RANDOM_DIR run_with_retry cargo build --release
        run_with_retry $SUDO cp $RANDOM_DIR/target/release/alacritty /usr/local/bin

        DIR=$RANDOM_DIR infocmp alacritty &>/dev/null
        if [ $? -ne 0 ]; then
            DIR=$RANDOM_DIR run_with_retry $SUDO tic -xe alacritty,alacritty-direct extra/alacritty.info
        fi

        rm -rf $RANDOM_DIR &>/dev/null

        # Create alacritty configuration
        STDOUT=/dev/null STDERR=/dev/null run_once mkdir -p "$HOME/.config/alacritty"
        if [ "_$DEBUG" == "_" ]; then
            run_with_retry curl "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/Configs/alacritty/alacritty.toml" \
                -o "$HOME/.config/alacritty/alacritty.toml"
        else
            run_with_retry cp "$SCRIPT_DIR/../Configs/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"
        fi
    fi
fi

# Install C++ environment
if [ -z "$SKIP_CXX" ]; then
    resp=$(ask "Install C++ environment? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install clang, clang-format, gcc, cmake"
        run_with_retry $SUDO apt-get install -y clang clang-format gcc cmake lldb

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
        if [ ! -z "$(which cargo 2>/dev/null)" ]; then
            info "Install delta using cargo"
            STDOUT=/dev/null STDERR=/dev/null run_with_retry cargo install git-delta
        else
            info "Install delta using github release"
            release=$(curl --silent -m 10 --connect-timeout 5 "https://api.github.com/repos/dandavison/delta/releases/latest")
            tag=$(echo "$release" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            tmpdir=$(mktemp -d)
            STDOUT=/dev/null STDERR=/dev/null run_with_retry wget --quiet -P "$tmpdir" "https://github.com/dandavison/delta/releases/download/$tag/delta-$tag-x86_64-unknown-linux-gnu.tar.gz"
            STDOUT=/dev/null STDERR=/dev/null run_with_retry dpkg -i "$tmpdir/delta-$tag-x86_64-unknown-linux-gnu.tar.gz"
            rm -rf $tmpdir
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
fi

if [ -f "$HOME/.config/alacritty" ]; then
    warn "If alacritty doesn't show rendered font, try using this: alacritty -o 'debug.renderer=\"gles2\"'"
fi

delete_log
