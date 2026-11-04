#!/bin/bash
# Claude Code.

module claude --no-minimal --desc "Claude Code"

# The native installer puts claude into ~/.local/bin and updates it by itself
function claude_install {
    if command -v claude >/dev/null 2>&1; then
        return 0
    fi
    download https://claude.ai/install.sh "$TMPDIR/claude-install.sh"
    run bash "$TMPDIR/claude-install.sh"
}
