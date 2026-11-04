#!/bin/bash
# Base requirements of all other modules, zoxide and the owned bash snippet.

module base --core --required --after upgrade --desc "base requirements" \
    --packages "ca-certificates git python unzip wget less curl gnupg fzf pipx" \
    --packages-debian "python3-venv"

function base_prepare {
    if ! command -v zoxide >/dev/null 2>&1; then
        choose_upstream zoxide zoxide
    fi
}

# Remove the blocks appended by the legacy setup scripts
function _migrate_legacy_blocks {
    local f tmp
    for f in "$HOME/.bashrc" "$HOME/.config/fish/config.fish"; do
        [ -f "$f" ] || continue
        tmp="$TMPDIR/legacy-$RANDOM"
        awk '
            function flush() { if (held) { print ""; held = 0 } }
            skip > 0 { skip--; next }
            $0 == "" { flush(); held = 1; next }
            $0 == "# ZOXIDE INIT" { held = 0; skip = 1; next }
            $0 == "# CAT ALIAS" || $0 == "# LOCAL BIN" || $0 == "# CARGO BIN" { held = 0; skip = 2; next }
            $0 == "export PATH=$PATH:~/.local/bin" || $0 == "export PATH=$PATH:~/.cargo/bin" { next }
            { flush(); print }
            END { flush() }
        ' "$f" >"$tmp"
        if ! cmp -s "$f" "$tmp"; then
            backup_file "$f"
            cat "$tmp" >"$f"
            note "Removed legacy blocks from $f"
        fi
    done
}

# Install zoxide from the GitHub release. Its install script leaves files in /tmp.
function _zoxide_upstream {
    local tag dir="$TMPDIR/zoxide"
    tag="$(github_latest_tag ajeetdsouza/zoxide)"
    download "https://github.com/ajeetdsouza/zoxide/releases/download/$tag/zoxide-${tag#v}-$(uname -m)-unknown-linux-musl.tar.gz" "$dir/zoxide.tar.gz"
    run tar -xzf "$dir/zoxide.tar.gz" -C "$dir"
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$dir/zoxide" "$HOME/.local/bin/zoxide"
}

function base_install {
    if ! command -v zoxide >/dev/null 2>&1; then
        if use_upstream zoxide; then
            _zoxide_upstream
        else
            pkg_install zoxide
        fi
    fi

    _migrate_legacy_blocks

    write_owned "$HOME/.config/env-setup/bashrc.sh" <<'SNIPPET'
# Managed by env-setup, rewritten on every run. Do not edit.
for _env_setup_dir in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
    case ":$PATH:" in
    *":$_env_setup_dir:"*) ;;
    *) PATH="$PATH:$_env_setup_dir" ;;
    esac
done
unset _env_setup_dir
export PATH
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init --cmd cd bash)"
fi
SNIPPET
    touch "$HOME/.bashrc"
    ensure_line "$HOME/.bashrc" '[ -f ~/.config/env-setup/bashrc.sh ] && . ~/.config/env-setup/bashrc.sh'
}
