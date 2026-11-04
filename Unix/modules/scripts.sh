#!/bin/bash
# Utility scripts in ~/.local/bin.

module scripts --desc "utility scripts"

function scripts_install {
    local sc
    add_to_path "$HOME/.local/bin"
    for sc in git-sync git-check git-hooks dbg finance win-move; do
        put "Scripts/$sc" "$HOME/.local/bin/$sc" 755
    done
}
