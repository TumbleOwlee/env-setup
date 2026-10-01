#!/bin/bash
set -o pipefail

# Get location of script to allow call from any location
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

SUDO=sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=
fi

# Install all required tools from the official repositories
$SUDO pacman -Syu --needed --noconfirm - <"${SCRIPT_DIR}/packages.txt" || exit 1

# Install AUR packages if an AUR helper is available
if command -v yay >/dev/null 2>&1; then
    yay -S --needed --noconfirm - <"${SCRIPT_DIR}/aur-packages.txt" ||
        echo "WARNING: yay failed to install some AUR packages" >&2
else
    echo "WARNING: yay not found, skipping AUR packages:" >&2
    sed 's/^/    /' "${SCRIPT_DIR}/aur-packages.txt" >&2
fi

# Install default environment configuration
mkdir -p ~/.config ~/.screenlayout ~/.backgrounds
cp -rT "${SCRIPT_DIR}/.config" ~/.config
cp -rT "${SCRIPT_DIR}/.screenlayout" ~/.screenlayout
cp -rT "${SCRIPT_DIR}/.backgrounds" ~/.backgrounds
cp "${SCRIPT_DIR}/.gtkrc-2.0" ~/.gtkrc-2.0
