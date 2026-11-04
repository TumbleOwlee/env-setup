#!/bin/bash
# Utility scripts in ~/.local/bin.

module scripts --desc "utility scripts"

function scripts_install {
    local sc
    for sc in git-sync git-check git-hooks dbg finance win-move; do
        put "Scripts/$sc" "$HOME/.local/bin/$sc" 755
    done
}
