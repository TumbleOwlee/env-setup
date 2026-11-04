#!/bin/bash
# The bspwm desktop. Overwrites existing files of the same name, therefore off by default.

module desktop --optional --no-minimal --distros "arch" --deps "yay" --desc "bspwm desktop (overwrites existing configuration)"

function desktop_install {
    local env="$ROOT/Environment" pkgs aur
    mapfile -t pkgs <"$env/packages.txt"
    mapfile -t aur <"$env/aur-packages.txt"
    pkg_install "${pkgs[@]}"
    if [ "$(id -u)" -eq 0 ]; then
        note "yay doesn't run as root, install these AUR packages as a user: ${aur[*]}"
    else
        # AUR packages break independently of this setup, the desktop works without most of them
        if ! run yay -S --needed --noconfirm "${aur[@]}"; then
            note "yay could not install all of these AUR packages: ${aur[*]}. See the log."
        fi
    fi

    mkdir -p "$HOME/.config" "$HOME/.screenlayout" "$HOME/.backgrounds" "$HOME/.config/dotstrap"
    cp -rT "$env/.config" "$HOME/.config"
    cp -rT "$env/.screenlayout" "$HOME/.screenlayout"
    cp -rT "$env/.backgrounds" "$HOME/.backgrounds"
    cp "$env/.gtkrc-2.0" "$HOME/.gtkrc-2.0"
    # Local machine config: never overwrite an existing one
    if [ ! -f "$HOME/.config/dotstrap/local.conf" ]; then
        cp "$env/local.conf.example" "$HOME/.config/dotstrap/local.conf"
    fi
}
