#!/bin/bash
# Stage 2 for Arch Linux. Started by Unix/setup.sh (exec in DEBUG mode, from a
# temp file otherwise) with DEBUG exported and the arguments passed through.
#
# AUR note: every package this setup installs (git, base-devel, less, neovim,
# ninja, fish, tmux, fontconfig, unzip, docker, docker-compose, rustup, clang,
# gcc, cmake, lldb, alacritty, git-delta, mise, zoxide, fzf, python-pipx, ...)
# is in the official repositories (core/extra). Only yay itself comes from the
# AUR. Therefore no AUR wrapper for root is needed: pkg_install (common.sh) uses
# pacman when running as root, because yay refuses to run as root.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
BASE_URL="${ENV_SETUP_URL:-https://raw.githubusercontent.com/TumbleOwlee/env-setup/main}"

export DISTRO=arch
USER="$(id -un)"

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
        NAME="$(echo "$NAME" | tr '[:lower:]' '[:upper:]')"
        export "SKIP_$NAME=YES"
        ;;
    *) ;;
    esac
done

# Load helpers and steps
if [ -n "$DEBUG" ]; then
    # shellcheck source=Unix/common.sh
    source "$SCRIPT_DIR/../common.sh" || exit 1
    # shellcheck source=Unix/steps.sh
    source "$SCRIPT_DIR/../steps.sh" || exit 1
else
    common_tmp="$(mktemp)" || exit 1
    if ! curl -fsSL "$BASE_URL/Unix/common.sh" -o "$common_tmp" || [ ! -s "$common_tmp" ]; then
        rm -f "$common_tmp"
        echo "Failed to download $BASE_URL/Unix/common.sh" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$common_tmp" || exit 1
    rm -f "$common_tmp"
    source_remote Unix/steps.sh
fi

# Print the newest non-debug yay-bin package built in <dir>
function _yay_pkg {
    find "$1" -maxdepth 1 -name 'yay-bin-*.pkg.tar.*' ! -name '*-debug-*' | head -n 1
}

# Remove the temporary build user and its sudoers drop-in
function _yay_builder_cleanup {
    rm -f /etc/sudoers.d/makepkg-builder
    if getent passwd makepkg-builder >/dev/null 2>&1; then
        userdel -r makepkg-builder >/dev/null 2>&1
    fi
}

# Build yay as the temporary makepkg-builder user (we are root)
function _yay_bootstrap_root {
    local dir="$1" rc=0 pkg
    getent passwd makepkg-builder >/dev/null 2>&1 || useradd -m makepkg-builder || return 1
    mkdir -p /etc/sudoers.d
    echo 'makepkg-builder ALL=(ALL) NOPASSWD: /usr/bin/pacman' >/etc/sudoers.d/makepkg-builder
    chmod 440 /etc/sudoers.d/makepkg-builder
    if ! visudo -cf /etc/sudoers.d/makepkg-builder >/dev/null; then
        error "Invalid sudoers drop-in."
        _yay_builder_cleanup
        return 1
    fi
    chown -R makepkg-builder: "$dir"
    if run_with_retry runuser -l makepkg-builder -c \
        "git clone https://aur.archlinux.org/yay-bin.git '$dir/yay-bin' && cd '$dir/yay-bin' && makepkg -s --noconfirm"; then
        pkg="$(_yay_pkg "$dir/yay-bin")"
        if [ -n "$pkg" ]; then
            run_with_retry pacman -U --noconfirm "$pkg" || rc=1
        else
            error "yay-bin package was not built."
            rc=1
        fi
    else
        rc=1
    fi
    _yay_builder_cleanup
    return "$rc"
}

# Build yay as the current non-root user
function _yay_bootstrap_user {
    local dir="$1" pkg
    run_with_retry git clone https://aur.archlinux.org/yay-bin.git "$dir/yay-bin" || return 1
    DIR="$dir/yay-bin" run_with_retry makepkg -s --noconfirm || return 1
    pkg="$(_yay_pkg "$dir/yay-bin")"
    if [ -z "$pkg" ]; then
        error "yay-bin package was not built."
        return 1
    fi
    run_with_retry "$SUDO" pacman -U --noconfirm "$pkg"
}

# Install yay (AUR helper) if missing
function install_yay {
    command -v yay >/dev/null 2>&1 && return 0
    info "Install yay."
    local tmpdir rc=0
    tmpdir="$(mktemp -d)" || return 1
    if [ "$(id -u)" -eq 0 ]; then
        _yay_bootstrap_root "$tmpdir" || rc=1
    else
        _yay_bootstrap_user "$tmpdir" || rc=1
    fi
    rm -rf "$tmpdir"
    return "$rc"
}

# Cache sudo privileges, ask for proxy
check_sudo
check_proxy

resp=$(ask "Update and upgrade? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Update and upgrade."
    # shellcheck disable=SC2086 # SUDO is empty or a single word
    run_with_retry $SUDO pacman -Syu --noconfirm
fi

# shellcheck disable=SC2086
run_with_retry $SUDO pacman -S --needed --noconfirm git base-devel less
install_yay || exit 1

step_base || exit 1
step_fish
step_tmux

if _step_wanted NEOVIM "neovim"; then
    pkg_install neovim ninja
    step_fonts
fi
step_neovim_config

step_docker
step_rust
step_cxx

if _step_wanted ALACRITTY "alacritty"; then
    pkg_install alacritty
    step_fonts
    step_alacritty_config
    notify "If alacritty doesn't render the font, try: alacritty -o 'debug.renderer=\"gles2\"'"
fi

step_delta
step_scripts
step_mise

delete_log
