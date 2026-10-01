#!/bin/bash
# Stage 2 setup for Debian and Ubuntu. Started by Unix/setup.sh (DEBUG is exported).

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
BASE_URL="${ENV_SETUP_URL:-https://raw.githubusercontent.com/TumbleOwlee/env-setup/main}"
DISTRO=debian

JOBS=1
NPROC=$(nproc 2>/dev/null)
if [ -n "$NPROC" ] && [ "$NPROC" -gt 2 ]; then
    JOBS=$((NPROC - 1))
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
        NAME="$(echo "$NAME" | tr '[:lower:]' '[:upper:]')"
        export "SKIP_$NAME=YES"
        ;;
    *) ;;
    esac
done

# Include helpers and shared steps
if [ -n "$DEBUG" ]; then
    # shellcheck source=Unix/common.sh
    source "$SCRIPT_DIR/../common.sh" || exit 1
    # shellcheck source=Unix/steps.sh
    source "$SCRIPT_DIR/../steps.sh" || exit 1
else
    command -v curl >/dev/null 2>&1 || {
        echo "curl is required." >&2
        exit 1
    }
    common_tmp="$(mktemp)" || exit 1
    if ! curl -fsSL "$BASE_URL/Unix/common.sh" -o "$common_tmp" || [ ! -s "$common_tmp" ]; then
        rm -f "$common_tmp"
        echo "Failed to download common.sh." >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$common_tmp" || exit 1
    rm -f "$common_tmp"
    source_remote Unix/steps.sh
fi

[ -n "$NO_CONFIRM" ] && export DEBIAN_FRONTEND=noninteractive

# Cache sudo privileges and set $SUDO
check_sudo

# Ask for proxy
check_proxy

# Empty when running as root
SUDO_CMD=()
[ -n "$SUDO" ] && SUDO_CMD=("$SUDO")

# Update package lists (always needed for installs) and optionally upgrade
info "Update package lists."
run_with_retry "${SUDO_CMD[@]}" apt-get update || exit 1
resp=$(ask "Update and upgrade? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    run_with_retry "${SUDO_CMD[@]}" apt-get upgrade -y
fi

# add-apt-repository and friends are Ubuntu only
OS_ID="$(sed -n 's/^ID=//p' "${OS_RELEASE_FILE:-/etc/os-release}" | head -n 1 | tr -d "\"'")"
if [ "$OS_ID" == "ubuntu" ]; then
    pkg_install software-properties-common
fi

# Base requirements, zoxide and the bash snippet
step_base || exit 1

# pipx fallback for releases without a pipx package
if ! command -v pipx >/dev/null 2>&1; then
    info "Install pipx using pip."
    pkg_install python3-pip
    run_once python3 -m pip install --user pipx ||
        run_with_retry python3 -m pip install --user --break-system-packages pipx
fi

step_fish
step_tmux

# Latest stable neovim tag, empty if it can't be determined
function neovim_latest_tag {
    curl -fsSL -m 10 --connect-timeout 5 https://api.github.com/repos/neovim/neovim/releases/latest 2>/dev/null |
        sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1
}

# Build neovim from the stable branch unless the latest stable is installed
function neovim_upstream {
    local tag current tmpdir rc
    tag="$(neovim_latest_tag)"
    current="$(nvim --version 2>/dev/null | sed -n '1s/^NVIM *//p')"
    if [ -n "$tag" ] && [ "$tag" == "$current" ]; then
        notify "Neovim $current is already the latest stable release."
        return 0
    fi
    pkg_install ninja gettext cmake curl build-essential unzip || return 1
    tmpdir="$(mktemp -d)" || return 1
    run_with_retry git clone --depth=1 --branch stable https://github.com/neovim/neovim "$tmpdir"
    DIR="$tmpdir" run_with_retry make -j"$JOBS" CMAKE_BUILD_TYPE=RelWithDebInfo &&
        DIR="$tmpdir" run_with_retry "${SUDO_CMD[@]}" make install
    rc=$?
    "${SUDO_CMD[@]}" rm -rf "$tmpdir"
    return "$rc"
}

# Neovim
if [ -z "$SKIP_NEOVIM" ]; then
    resp=$(ask "Install neovim? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        info "Install neovim"
        if choose_source neovim "$(pkg_version neovim)"; then
            neovim_upstream
        else
            pkg_install neovim
        fi
        step_fonts
        step_neovim_config
    fi
fi

step_docker

# Alacritty decides whether rust is required
REQUIRE_RUST=0
if [ -z "$SKIP_ALACRITTY" ]; then
    resp_alacritty=$(ask "Install alacritty? [Y/n]" "Y")
    if [ "_$resp_alacritty" != "_n" ] && [ "_$resp_alacritty" != "_N" ]; then
        REQUIRE_RUST=1
    fi
fi

if [ "$REQUIRE_RUST" -eq 1 ]; then
    # Required by the alacritty build: no prompt, ignore a skip request
    unset SKIP_RUST
    NO_CONFIRM=YES step_rust
else
    step_rust
fi

step_cxx

# Build alacritty from source unless it is installed already
function alacritty_build {
    local tmpdir rc=0
    if command -v alacritty >/dev/null 2>&1; then
        notify "Alacritty already installed."
        return 0
    fi
    info "Install alacritty"
    pkg_install cmake g++ pkg-config libfreetype6-dev libfontconfig1-dev \
        libxcb-xfixes0-dev libxkbcommon-dev python3 git || return 1
    command -v cargo >/dev/null 2>&1 || {
        error "cargo is required to build alacritty."
        return 1
    }
    tmpdir="$(mktemp -d)" || return 1
    run_with_retry git clone --depth=1 https://github.com/alacritty/alacritty.git "$tmpdir" &&
        DIR="$tmpdir" run_with_retry cargo build --release &&
        run_with_retry "${SUDO_CMD[@]}" install -m 755 "$tmpdir/target/release/alacritty" /usr/local/bin/alacritty ||
        rc=1
    if [ "$rc" -eq 0 ] && ! infocmp alacritty >/dev/null 2>&1; then
        DIR="$tmpdir" run_with_retry "${SUDO_CMD[@]}" tic -xe alacritty,alacritty-direct extra/alacritty.info
        rc=$?
    fi
    rm -rf "$tmpdir"
    return "$rc"
}

if [ "$REQUIRE_RUST" -eq 1 ]; then
    alacritty_build
    step_alacritty_config
fi

step_delta
step_scripts
step_mise

if [ -d "$HOME/.config/alacritty" ]; then
    warn "If alacritty doesn't show rendered font, try using this: alacritty -o 'debug.renderer=\"gles2\"'"
fi

delete_log
