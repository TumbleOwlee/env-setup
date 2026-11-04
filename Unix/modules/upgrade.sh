#!/bin/bash
# System upgrade. Refreshes the package lists first.

module upgrade --core --desc "system upgrade"

function upgrade_install_arch {
    run root pacman -Syu --noconfirm
    touch "$WORK/pkg-synced"
}

function upgrade_install_debian {
    pkg_sync
    apt_get upgrade
}
