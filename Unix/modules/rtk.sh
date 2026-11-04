#!/bin/bash
# rtk and its Claude Code hook.

module rtk --no-minimal --desc "rtk and its Claude Code hook" --after "claude"

function rtk_install {
    if ! command -v rtk >/dev/null 2>&1; then
        run_installer https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh
    fi
    # rtk init fails if ~/.claude is missing. It's safe to run again.
    mkdir -p "$HOME/.claude"
    run rtk init -g --auto-patch --no-trust-filters
}
