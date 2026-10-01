#!/bin/bash
# Stage 1 entry point. Standalone: must not depend on common.sh so it can run via
#   bash <(curl -fsSL https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/setup.sh)

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
BASE_URL="${ENV_SETUP_URL:-https://raw.githubusercontent.com/TumbleOwlee/env-setup/main}"

DEBUG=""
for i in "$@"; do
    case $i in
    -d | --debug)
        DEBUG=y
        ;;
    *) ;;
    esac
done
export DEBUG

# Map /etc/os-release (or $OS_RELEASE_FILE) to a supported distro directory
function detect_distro {
    local file="${OS_RELEASE_FILE:-/etc/os-release}" id="" id_like="" d
    [ -r "$file" ] || return 1
    id="$(sed -n 's/^ID=//p' "$file" | head -n 1 | tr -d '"'"'"'')"
    id_like="$(sed -n 's/^ID_LIKE=//p' "$file" | head -n 1 | tr -d '"'"'"'')"
    for d in $id $id_like; do
        case "$d" in
        arch)
            echo Arch
            return 0
            ;;
        debian | ubuntu)
            echo Debian
            return 0
            ;;
        esac
    done
    return 1
}

function try_install() {
    local pkg="$1" sudo_cmd=""
    if command -v "$pkg" >/dev/null 2>&1; then
        return 0
    fi
    if [ "$(id -u)" != "0" ] && command -v sudo >/dev/null 2>&1; then
        sudo_cmd=sudo
    fi
    case "$DISTRO_DIR" in
    Arch)
        $sudo_cmd pacman -Sy --noconfirm "$pkg" || {
            echo "Failed to install missing '$pkg'" >&2
            return 1
        }
        ;;
    Debian)
        if ! $sudo_cmd apt-get update || ! $sudo_cmd apt-get install -y "$pkg"; then
            echo "Failed to install missing '$pkg'" >&2
            return 1
        fi
        ;;
    esac
    command -v "$pkg" >/dev/null 2>&1 || {
        echo "'$pkg' could not be found" >&2
        return 1
    }
}

DISTRO_DIR="$(detect_distro)" || {
    echo "Unsupported distribution (supported: Arch, Debian/Ubuntu)." >&2
    exit 1
}

if [ -n "$DEBUG" ]; then
    echo "[?] Debug mode active." >&2
    exec bash "$SCRIPT_DIR/$DISTRO_DIR/setup.sh" "$@"
fi

try_install curl || exit 1

tmp="$(mktemp)" || exit 1
trap 'rm -f "$tmp"' EXIT
url="$BASE_URL/Unix/$DISTRO_DIR/setup.sh"
if ! curl -fsSL "$url" -o "$tmp" || [ ! -s "$tmp" ]; then
    echo "Failed to download $url" >&2
    exit 1
fi
# No exec: keep the EXIT trap so the temp file is removed afterwards
bash "$tmp" "$@"
