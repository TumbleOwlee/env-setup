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
    migrate_config_dir
    _migrate_paths

    # pipx and the upstream zoxide install into ~/.local/bin
    add_to_path "${PIPX_BIN_DIR:-$HOME/.local/bin}"
    add_command_to_path zoxide

    # POSIX sh: ~/.profile is also read by sh, e.g. for a graphical login
    write_owned "$HOME/.config/dotstrap/bashrc.sh" <<'SNIPPET'
# Managed by dotstrap, rewritten on every run. Do not edit.
# Adds the directories in ~/.config/dotstrap/paths to PATH.
if [ -f "$HOME/.config/dotstrap/paths" ]; then
    while IFS= read -r _dotstrap_dir; do
        [ -n "$_dotstrap_dir" ] || continue
        case ":$PATH:" in
        *":$_dotstrap_dir:"*) ;;
        *) PATH="$PATH:$_dotstrap_dir" ;;
        esac
    done <"$HOME/.config/dotstrap/paths"
    unset _dotstrap_dir
    export PATH
fi
if [ -n "${BASH_VERSION:-}" ]; then
    case "$-" in
    *i*)
        if command -v zoxide >/dev/null 2>&1; then
            eval "$(zoxide init --cmd cd bash)"
        fi
        ;;
    esac
fi
SNIPPET
    _source_snippet "$HOME/.bashrc"
    # Login shells, also non-interactive ones like 'bash -lc' or 'ssh host cmd' with
    # a login shell. bash reads ~/.bash_profile instead of ~/.profile if it exists.
    _source_snippet "$HOME/.profile"
    if [ -f "$HOME/.bash_profile" ]; then
        _source_snippet "$HOME/.bash_profile"
    fi
}

# Source the snippet at the end of a shell startup file: _source_snippet <file>
function _source_snippet {
    touch "$1"
    migrate_source_line "$1"
    ensure_line "$1" '[ -f ~/.config/dotstrap/bashrc.sh ] && . ~/.config/dotstrap/bashrc.sh'
}

# Older versions always added ~/.local/bin and ~/.cargo/bin. Keep the existing ones
# for the first run with the paths file, as tools might have been installed there.
function _migrate_paths {
    local d
    if [ -f "$PATHS_FILE" ] || [ ! -f "$HOME/.config/dotstrap/bashrc.sh" ]; then
        return 0
    fi
    for d in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
        if [ -d "$d" ]; then
            add_to_path "$d"
        fi
    done
}
