#!/bin/bash
# Entry point. Standalone, so it also works piped into bash:
#   curl -fsSL https://raw.githubusercontent.com/TumbleOwlee/dotstrap/main/Unix/setup.sh | bash -s -- [flags]
# Uses the files next to it in a checkout, otherwise downloads one tarball of
# DOTSTRAP_REF. Everything is inside main so a truncated download can't run partially.

function fetch_to {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        echo "Neither curl nor wget found. Install one of them and run again." >&2
        return 1
    fi
}

function main {
    local dir tool url
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
        if [ -f "$dir/lib/main.sh" ]; then
            exec bash "$dir/lib/main.sh" "$@" </dev/null
        fi
    fi

    for tool in tar gzip mktemp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "'$tool' is required but missing." >&2
            exit 1
        fi
    done

    url="${DOTSTRAP_REPO:-https://github.com/TumbleOwlee/dotstrap}/archive/${DOTSTRAP_REF:-main}.tar.gz"
    DOWNLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotstrap-download.XXXXXX")" || exit 1
    trap 'rm -rf -- "$DOWNLOAD_DIR"' EXIT
    if ! fetch_to "$url" "$DOWNLOAD_DIR/repo.tar.gz"; then
        echo "Failed to download $url" >&2
        exit 1
    fi
    if ! tar -xzf "$DOWNLOAD_DIR/repo.tar.gz" --strip-components=1 -C "$DOWNLOAD_DIR" || [ ! -f "$DOWNLOAD_DIR/Unix/lib/main.sh" ]; then
        echo "Invalid archive from $url" >&2
        exit 1
    fi
    # No exec: keep the EXIT trap so the download is removed afterwards
    bash "$DOWNLOAD_DIR/Unix/lib/main.sh" "$@" </dev/null
}

main "$@"
