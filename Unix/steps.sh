#!/bin/bash
# shellcheck disable=SC2034 # PIPE is consumed by run_with_retry from common.sh
# Shared, idempotent install steps. Only function definitions, nothing runs at
# source time. Requires Unix/common.sh to be sourced first. Each step honors
# SKIP_<NAME> and asks its [Y/n] prompt (NO_CONFIRM answers the default).

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Print the distro family (arch|debian)
function _steps_distro {
    echo "${DISTRO:-$(detect_distro)}"
}

# Print the target user name
function _steps_user {
    echo "${USER:-$(id -un)}"
}

# Return 0 if the step <NAME> is not skipped and the user confirms <label>
# With ASKED=1 the caller already got a yes for this tool: no second prompt.
function _step_wanted {
    local var="SKIP_$1" resp
    [ -z "${!var}" ] || return 1
    [ "${ASKED:-}" != "1" ] || return 0
    resp=$(ask "Install $2? [Y/n]" "Y")
    [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]
}

# Return 0 if the upstream release should be used: _use_upstream <tool> <logical-pkg>
function _use_upstream {
    local ver
    ver="$(pkg_version "$2")" || return 0
    choose_source "$1" "$ver"
}

# Write stdin to <dest> only if the content differs (keeps the file untouched otherwise)
function _write_owned {
    local dest="$1" tmp
    tmp="$(mktemp)" || return 1
    cat >"$tmp"
    mkdir -p "$(dirname "$dest")" || {
        rm -f "$tmp"
        return 1
    }
    if ! cmp -s "$tmp" "$dest"; then
        cat "$tmp" >"$dest"
    fi
    rm -f "$tmp"
}

# Fetch a repo file to <dest>: _fetch_install <repo-path> <dest> <mode> [backup]
# Skips if identical, backs up a differing existing file when 'backup' is given.
function _fetch_install {
    local src="$1" dest="$2" mode="$3" backup="${4:-}" tmp
    tmp="$(mktemp)" || return 1
    mkdir -p "$(dirname "$dest")" || {
        rm -f "$tmp"
        return 1
    }
    if ! fetch "$src" "$tmp" || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        error "Failed to fetch '$src'."
        return 1
    fi
    chmod "$mode" "$tmp"
    if cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        chmod "$mode" "$dest"
        return 0
    fi
    [ "$backup" == "backup" ] && backup_file "$dest"
    mv "$tmp" "$dest" || {
        rm -f "$tmp"
        return 1
    }
}

# Download one URL to dest atomically
function _download_once {
    local tmp
    tmp="$(mktemp)" || return 1
    if ! curl -fsSL "$1" -o "$tmp" || ! mv "$tmp" "$2"; then
        rm -f "$tmp"
        return 1
    fi
}

# Download any URL to <dest> with retry: _download <url> <dest>
function _download {
    run_with_retry _download_once "$1" "$2"
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

# Base requirements, zoxide and the owned bash snippet
function step_base {
    info "Install requirements."
    local pkgs=(git python unzip wget less curl gnupg fzf)
    if [ "$(_steps_distro)" == "debian" ]; then
        pkgs+=(python3-venv)
        # Older releases have no pipx package, the distro script falls back to pip
        pkg_version pipx >/dev/null 2>&1 && pkgs+=(pipx)
    else
        pkgs+=(pipx)
    fi
    pkg_install "${pkgs[@]}" || return 1

    if ! command -v zoxide >/dev/null 2>&1; then
        if _use_upstream zoxide zoxide; then
            info "Install zoxide from upstream."
            PIPE=(sh)
            run_with_retry curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh
        else
            info "Install zoxide."
            pkg_install zoxide
        fi
    fi

    migrate_legacy_blocks

    _write_owned "$HOME/.config/env-setup/bashrc.sh" <<'SNIPPET'
# Managed by env-setup, rewritten on every run. Do not edit.
for _env_setup_dir in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
    case ":$PATH:" in
    *":$_env_setup_dir:"*) ;;
    *) PATH="$PATH:$_env_setup_dir" ;;
    esac
done
unset _env_setup_dir
export PATH
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init --cmd cd bash)"
fi
SNIPPET
    touch "$HOME/.bashrc"
    ensure_line "$HOME/.bashrc" '[ -f ~/.config/env-setup/bashrc.sh ] && . ~/.config/env-setup/bashrc.sh'

    case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$PATH:$HOME/.local/bin" ;;
    esac
}

# Point tmux at fish through the local override file, if fish exists
function _tmux_default_shell {
    local fish_path
    fish_path="$(command -v fish)" || return 0
    _write_owned "$HOME/.config/tmux/env-setup.local.conf" <<EOF
# Managed by env-setup, rewritten on every run. Do not edit.
set -g default-shell $fish_path
EOF
}

# Fish shell, functions and the owned conf.d snippet
function step_fish {
    _step_wanted FISH "fish shell" || return 0
    info "Install fish shell"
    pkg_install fish || return 1
    migrate_legacy_blocks

    local fish_path user shell sudo=()
    fish_path="$(command -v fish)" || return 1
    user="$(_steps_user)"
    [ -n "$SUDO" ] && sudo=("$SUDO")

    if ! grep -qxF "$fish_path" /etc/shells 2>/dev/null; then
        printf '%s\n' "$fish_path" | "${sudo[@]}" tee -a /etc/shells >/dev/null
    fi
    shell="$(getent passwd "$user" | cut -d: -f7)"
    if [ "$shell" != "$fish_path" ]; then
        run_with_retry "${sudo[@]}" chsh -s "$fish_path" "$user"
    fi

    local fn
    for fn in fish_greeting fish_prompt colored_cat; do
        _fetch_install "Unix/Configs/fish/$fn.fish" "$HOME/.config/fish/functions/$fn.fish" 644 || return 1
    done

    _write_owned "$HOME/.config/fish/conf.d/env-setup.fish" <<'SNIPPET'
# Managed by env-setup, rewritten on every run. Do not edit.
if functions -q fish_add_path
    fish_add_path -g $HOME/.local/bin $HOME/.cargo/bin
else
    for dir in $HOME/.local/bin $HOME/.cargo/bin
        contains $dir $PATH; or set PATH $dir $PATH
    end
end
if command -q zoxide
    zoxide init --cmd cd fish | source
end
alias ccat='command cat'
alias cat=colored_cat
if command -q nvim
    abbr -a vim nvim
    abbr -a vi nvim
    abbr -a v nvim
end
SNIPPET
    # Order independent: tmux may have been installed before fish
    if command -v tmux >/dev/null 2>&1; then
        _tmux_default_shell
    fi
}

# tmux and its local default-shell override
function step_tmux {
    _step_wanted TMUX "tmux" || return 0
    info "Install tmux"
    pkg_install tmux || return 1
    _fetch_install "Unix/Configs/tmux/tmux.conf" "$HOME/.tmux.conf" 644 backup || return 1

    _tmux_default_shell
}

# FiraCode Nerd Font
function step_fonts {
    _step_wanted FONTS "Nerd fonts" || return 0
    if command -v fc-list >/dev/null 2>&1 && fc-list | grep -qi 'FiraCode Nerd'; then
        notify "FiraCode Nerd Font already installed."
        return 0
    fi
    info "Install FiraCode Nerd Font"
    pkg_install fontconfig unzip || return 1
    local tmpdir
    tmpdir="$(mktemp -d)" || return 1
    mkdir -p "$HOME/.local/share/fonts/FiraCode"
    if _download https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip "$tmpdir/FiraCode.zip" &&
        run_with_retry unzip -o "$tmpdir/FiraCode.zip" -x README.md LICENSE -d "$HOME/.local/share/fonts/FiraCode"; then
        STDOUT=/dev/null STDERR=/dev/null run_once fc-cache -f
    fi
    rm -rf "$tmpdir"
}

# Neovim configuration (the nvim binary is installed by the distro script)
function step_neovim_config {
    _step_wanted NEOVIM "neovim configuration" || return 0
    info "Install/update nvim configuration"
    local dir="$HOME/.config/nvim" url="https://github.com/TumbleOwlee/neovim-config" resp
    if [ -d "$dir/.git" ]; then
        DIR="$dir" run_with_retry git pull --ff-only
    elif [ -e "$dir" ]; then
        resp=$(ask "Replace existing nvim configuration? [Y/n]" "Y")
        if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
            backup_file "$dir"
            rm -rf "$dir"
            run_with_retry git clone "$url" "$dir"
        else
            info "Skip installing nvim configuration"
        fi
    else
        mkdir -p "$HOME/.config"
        run_with_retry git clone "$url" "$dir"
    fi

    if nvim_usable; then
        run_once nvim --headless -c 'SyncInstall' -c qall
        run_with_retry nvim --headless -c 'SyncInstall' -c qall
        nvim_install_lsp "lua-language-server"
        nvim_install_lsp "python-lsp-server"
    elif command -v nvim >/dev/null 2>&1; then
        warn "Installed neovim is older than 0.12, skipping plugin sync. Use the upstream release."
    fi
}

# Rust toolchain and cargo tools
function step_rust {
    _step_wanted RUST "rust environment" || return 0
    info "Install rust"
    if ! command -v rustup >/dev/null 2>&1; then
        if _use_upstream rustup rustup; then
            PIPE=(sh -s -- -y --no-modify-path)
            run_with_retry curl -fsSL https://sh.rustup.rs || return 1
        else
            pkg_install rustup || return 1
        fi
    fi
    # shellcheck disable=SC1091
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    case ":$PATH:" in
    *":$HOME/.cargo/bin:"*) ;;
    *) export PATH="$PATH:$HOME/.cargo/bin" ;;
    esac

    run_with_retry rustup toolchain install stable || return 1
    run_with_retry rustup default stable
    run_with_retry rustup component add rust-src rust-analyzer

    pkg_install libclang
    if ! command -v cross >/dev/null 2>&1; then
        run_with_retry cargo install cross --git https://github.com/cross-rs/cross
    fi
    if ! command -v tree-sitter >/dev/null 2>&1; then
        run_with_retry cargo install --locked tree-sitter-cli
    fi
    nvim_install_lsp "rust-analyzer"
}

# C++ toolchain
function step_cxx {
    _step_wanted CXX "C++ environment" || return 0
    info "Install clang, gcc, cmake"
    local pkgs=(clang gcc cmake lldb)
    [ "$(_steps_distro)" == "debian" ] && pkgs+=(clang-format)
    pkg_install "${pkgs[@]}" || return 1
    nvim_install_lsp "clangd"

    local resp
    resp=$(ask "Install Conan? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        if pipx list --short 2>/dev/null | grep -q '^conan '; then
            notify "Conan already installed."
        else
            run_with_retry pipx install conan
        fi
    fi
}

# Docker
function step_docker {
    _step_wanted DOCKER "docker" || return 0
    info "Install docker"
    local pkgs=(docker compose) user sudo=()
    user="$(_steps_user)"
    [ -n "$SUDO" ] && sudo=("$SUDO")
    pkg_version docker-buildx >/dev/null 2>&1 && pkgs+=(docker-buildx)
    pkg_install "${pkgs[@]}" || return 1

    getent group docker >/dev/null 2>&1 || run_with_retry "${sudo[@]}" groupadd docker
    if ! getent group docker | cut -d: -f4 | tr ',' '\n' | grep -qxF "$user"; then
        run_with_retry "${sudo[@]}" usermod -aG docker "$user"
    fi
    if [ -d /run/systemd/system ]; then
        run_with_retry "${sudo[@]}" systemctl enable --now docker
    fi
}

# Install delta from the GitHub release
function _delta_upstream {
    local distro machine tag tmpdir sudo=() deb_arch triple rc
    distro="$(_steps_distro)"
    machine="$(uname -m)"
    [ -n "$SUDO" ] && sudo=("$SUDO")
    tag="$(curl -fsSL -m 10 --connect-timeout 5 https://api.github.com/repos/dandavison/delta/releases/latest |
        sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
    if [ -z "$tag" ]; then
        error "Could not determine the latest delta release."
        return 1
    fi
    tmpdir="$(mktemp -d)" || return 1
    local base="https://github.com/dandavison/delta/releases/download/$tag"
    if [ "$distro" == "debian" ]; then
        case "$machine" in
        x86_64) deb_arch=amd64 ;;
        aarch64) deb_arch=arm64 ;;
        *) deb_arch="$machine" ;;
        esac
        _download "$base/git-delta_${tag}_${deb_arch}.deb" "$tmpdir/delta.deb" &&
            run_with_retry "${sudo[@]}" dpkg -i "$tmpdir/delta.deb"
    else
        case "$machine" in
        x86_64) triple=x86_64-unknown-linux-musl ;;
        aarch64) triple=aarch64-unknown-linux-gnu ;;
        *) triple="$machine-unknown-linux-gnu" ;;
        esac
        _download "$base/delta-$tag-$triple.tar.gz" "$tmpdir/delta.tar.gz" &&
            run_with_retry tar -xzf "$tmpdir/delta.tar.gz" --strip-components=1 -C "$tmpdir" &&
            mkdir -p "$HOME/.local/bin" &&
            install -m 755 "$tmpdir/delta" "$HOME/.local/bin/delta"
    fi
    rc=$?
    rm -rf "$tmpdir"
    return "$rc"
}

# Delta and the git configuration
function step_delta {
    _step_wanted DELTA "delta" || return 0
    if ! command -v delta >/dev/null 2>&1; then
        if _use_upstream delta delta; then
            info "Install delta from the GitHub release"
            _delta_upstream || return 1
        else
            info "Install delta"
            pkg_install delta || return 1
        fi
    fi

    mkdir -p "$HOME/.config/delta" "$HOME/.config/git"
    _download https://raw.githubusercontent.com/dandavison/delta/main/themes.gitconfig \
        "$HOME/.config/delta/themes.gitconfig" || return 1

    local target="$HOME/.config/git/env-setup.gitconfig" regex
    _fetch_install "Unix/Configs/git/gitconfig" "$target" 644 || return 1
    regex="^$(printf '%s' "$target" | sed 's/[][\.*^$/]/\\&/g')\$"
    git config --global --replace-all include.path "$target" "$regex"
}

# Alacritty configuration
function step_alacritty_config {
    _step_wanted ALACRITTY "alacritty configuration" || return 0
    info "Install alacritty configuration"
    local dir="$HOME/.config/alacritty"
    mkdir -p "$dir"
    if [ -f "$dir/alacritty.yml" ]; then
        mv "$dir/alacritty.yml" "$dir/alacritty.yml.bak.$(date +%Y%m%d%H%M%S)"
    fi
    _fetch_install "Unix/Configs/alacritty/alacritty.toml" "$dir/alacritty.toml" 644 backup
}

# Utility scripts
function step_scripts {
    _step_wanted SCRIPTS "utility scripts" || return 0
    info "Install utility scripts"
    local sc
    mkdir -p "$HOME/.local/bin"
    for sc in git-sync git-check git-hooks dbg finance win-move; do
        _fetch_install "Unix/Scripts/$sc" "$HOME/.local/bin/$sc" 755 || return 1
    done
}

# mise
function step_mise {
    _step_wanted MISE "mise" || return 0
    command -v mise >/dev/null 2>&1 && return 0
    if _use_upstream mise mise; then
        info "Install mise from upstream"
        PIPE=(sh)
        run_with_retry curl -fsSL https://mise.run
    else
        info "Install mise"
        pkg_install mise
    fi
}
