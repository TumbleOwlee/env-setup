#!/bin/bash
# Docker, compose and buildx.

module docker --no-minimal --desc "docker"

function docker_install {
    local pkgs=(docker compose)
    pkg_sync
    if pkg_version docker-buildx >/dev/null; then
        pkgs+=(docker-buildx)
    fi
    pkg_install "${pkgs[@]}"

    if ! getent group docker >/dev/null 2>&1; then
        run root groupadd docker
    fi
    if ! getent group docker | cut -d: -f4 | tr ',' '\n' | grep -qxF "$USER"; then
        run root usermod -aG docker "$USER"
        note "Log in again to use docker without sudo."
    fi
    if [ -d /run/systemd/system ]; then
        run root systemctl enable --now docker
    fi
}
