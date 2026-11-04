#!/bin/bash
# caveman as Claude Code plugin.

module caveman --no-minimal --desc "caveman Claude Code plugin" --deps "claude"

# Return 0 if a plugin is installed in the user scope: _caveman_has_plugin <id>
function _caveman_has_plugin {
    claude plugin list --json | python3 -c '
import json, sys
sys.exit(not any(p.get("id") == sys.argv[1] and p.get("scope") == "user" for p in json.load(sys.stdin)))
' "$1"
}

function caveman_install {
    if claude plugin marketplace list --json | grep -q '"name": *"caveman"'; then
        run claude plugin marketplace update caveman
    else
        run claude plugin marketplace add JuliusBrussee/caveman
    fi
    if ! _caveman_has_plugin caveman@caveman; then
        run claude plugin install --scope user caveman@caveman
    fi
}
