#!/bin/bash
# yay, the AUR helper. All other packages of the setup are in the official
# repositories, only the desktop module needs it for the AUR packages.

module yay --no-minimal --distros "arch" --desc "yay" --packages "git base-devel"

YAY_BUILDER=makepkg-builder

# Print the newest non-debug yay-bin package built in <dir>
function _yay_pkg {
    find "$1" -maxdepth 1 -name 'yay-bin-*.pkg.tar.*' ! -name '*-debug-*' | head -n 1
}

# makepkg refuses to run as root: build as a temporary user, removed with its home afterwards
function _yay_build_as_builder {
    local dir="/home/$YAY_BUILDER/yay-bin" pkg
    mkdir -p /etc/sudoers.d
    echo "$YAY_BUILDER ALL=(ALL) NOPASSWD: /usr/bin/pacman" >"/etc/sudoers.d/$YAY_BUILDER"
    chmod 440 "/etc/sudoers.d/$YAY_BUILDER"
    visudo -cf "/etc/sudoers.d/$YAY_BUILDER" >/dev/null || return 1
    run runuser -l "$YAY_BUILDER" -c "git clone https://aur.archlinux.org/yay-bin.git '$dir' && cd '$dir' && makepkg -s --noconfirm" || return 1
    pkg="$(_yay_pkg "$dir")"
    [ -n "$pkg" ] || return 1
    run pacman -U --noconfirm "$pkg"
}

# Only called for the user created by yay_install
function _yay_builder_cleanup {
    rm -f -- "/etc/sudoers.d/$YAY_BUILDER"
    userdel -r "$YAY_BUILDER" >/dev/null 2>&1 || true
}

function yay_install {
    local pkg rc=0
    if command -v yay >/dev/null 2>&1; then
        return 0
    fi
    if [ "$(id -u)" -eq 0 ]; then
        # An existing user could be someone else's and must not be removed afterwards
        if getent passwd "$YAY_BUILDER" >/dev/null 2>&1; then
            echo "User $YAY_BUILDER already exists, not using it. Remove it if it's left over from an aborted run."
            return 1
        fi
        useradd -m "$YAY_BUILDER"
        _yay_build_as_builder || rc=$?
        _yay_builder_cleanup
        return "$rc"
    fi
    run git clone https://aur.archlinux.org/yay-bin.git "$TMPDIR/yay-bin"
    (
        cd "$TMPDIR/yay-bin" || exit 1
        run makepkg -s --noconfirm
    )
    pkg="$(_yay_pkg "$TMPDIR/yay-bin")"
    run root pacman -U --noconfirm "$pkg"
}
