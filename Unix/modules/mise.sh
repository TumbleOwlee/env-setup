#!/bin/bash
# mise.

module mise --no-minimal --desc "mise"

function mise_prepare {
    if ! command -v mise >/dev/null 2>&1; then
        choose_upstream mise mise
    fi
}

function mise_install {
    if command -v mise >/dev/null 2>&1; then
        return 0
    fi
    if use_upstream mise; then
        run_installer https://mise.run
    else
        pkg_install mise
    fi
}
