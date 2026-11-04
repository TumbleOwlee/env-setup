#!/bin/bash
# tmux and its local default-shell override.

module tmux --desc "tmux" --packages "tmux" --after "fish"

function tmux_install {
    local fish_path
    put "Configs/tmux/tmux.conf" "$HOME/.tmux.conf" 644 backup
    if fish_path="$(command -v fish)"; then
        write_owned "$HOME/.config/tmux/dotstrap.local.conf" <<SNIPPET
# Managed by dotstrap, rewritten on every run. Do not edit.
set -g default-shell $fish_path
SNIPPET
    fi
    # The snippet from when this project was called env-setup, ~/.tmux.conf no longer sources it
    rm -f -- "$HOME/.config/tmux/env-setup.local.conf"
}
