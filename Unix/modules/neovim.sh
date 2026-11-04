#!/bin/bash
# shellcheck disable=SC2034 # UPSTREAM belongs to helpers.sh
# Neovim, its configuration, plugins and language servers.

module neovim --desc "neovim and its configuration" --deps "rustup" \
    --packages-arch "neovim ninja gcc" --packages-debian "ninja gcc libc6-dev"

NEOVIM_CONFIG_URL="https://github.com/TumbleOwlee/neovim-config"
NEOVIM_KEEP_CONFIG=""
NEOVIM_PLUGINS="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"

# Return 0 if the packaged neovim is missing or older than 0.12
function _neovim_package_too_old {
    local ver
    ver="$(pkg_version neovim)" || return 0
    dpkg --compare-versions "$ver" lt 0.12
}

function neovim_prepare {
    local dir="$HOME/.config/nvim"
    if [ "$DISTRO" == "debian" ]; then
        UPSTREAM["neovim"]=1
        if [ -n "$INTERACTIVE" ] && ! _neovim_package_too_old; then
            choose_upstream neovim neovim
        fi
    fi
    if [ -e "$dir" ] && [ ! -d "$dir/.git" ]; then
        if ! confirm "Replace existing nvim configuration (a backup is kept)? [Y/n]" Y; then
            NEOVIM_KEEP_CONFIG=1
        fi
    fi
}

# Install the prebuilt upstream release into /opt/nvim unless the latest is installed
function _neovim_upstream {
    local tag current arch
    tag="$(github_latest_tag neovim/neovim)" || tag=""
    current="$(nvim --version 2>/dev/null | sed -n '1s/^NVIM *//p')" || current=""
    if [ -n "$tag" ] && [ "$tag" == "$current" ]; then
        return 0
    fi
    if [ -z "$tag" ] && nvim_usable; then
        note "Could not determine the latest neovim release, kept the installed one."
        return 0
    fi
    case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *)
        echo "No upstream neovim release for $(uname -m)."
        return 1
        ;;
    esac
    download "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$arch.tar.gz" "$TMPDIR/nvim.tar.gz"
    mkdir "$TMPDIR/nvim"
    run tar -xzf "$TMPDIR/nvim.tar.gz" -C "$TMPDIR/nvim" --strip-components=1
    # Refuse to delete or overwrite anything that is not a neovim release of this setup
    if [ -L /opt/nvim ] || { [ -e /opt/nvim ] && [ ! -x /opt/nvim/bin/nvim ]; }; then
        echo "/opt/nvim exists and is no neovim release, not replacing it."
        return 1
    fi
    if [ -e /usr/local/bin/nvim ] && [ "$(readlink /usr/local/bin/nvim)" != "/opt/nvim/bin/nvim" ]; then
        echo "/usr/local/bin/nvim exists and doesn't belong to this setup, not replacing it."
        return 1
    fi
    run root rm -rf -- /opt/nvim.new
    run root cp -r "$TMPDIR/nvim" /opt/nvim.new
    run root chmod -R a+rX /opt/nvim.new
    run root rm -rf -- /opt/nvim
    run root mv /opt/nvim.new /opt/nvim
    run root ln -sfn /opt/nvim/bin/nvim /usr/local/bin/nvim
    hash -r
}

function _neovim_config {
    local dir="$HOME/.config/nvim"
    if [ -d "$dir/.git" ]; then
        run git -C "$dir" pull --ff-only
    elif [ -z "$NEOVIM_KEEP_CONFIG" ]; then
        if [ -e "$dir" ] || [ -L "$dir" ]; then
            mv -- "$dir" "$dir.bak.$(date +%Y%m%d%H%M%S)"
        fi
        mkdir -p "$HOME/.config"
        run git clone "$NEOVIM_CONFIG_URL" "$dir"
    fi
}

# Print the plugins without a commit or with missing tracked files, as an interrupted
# clone leaves them. SyncInstall only checks that their directories exist.
function _neovim_damaged_plugins {
    local dir
    for dir in "$NEOVIM_PLUGINS"/*/; do
        if [ ! -L "${dir%/}" ] && [ -e "$dir.git" ]; then
            if ! git -C "$dir" rev-parse -q --verify HEAD >/dev/null 2>&1 || [ -n "$(git -C "$dir" ls-files -d)" ]; then
                basename "$dir"
            fi
        fi
    done
}

# Move plugins out of the way, so they get cloned again. Moved instead of deleted,
# because they could contain local changes: _neovim_move_plugins <name>...
function _neovim_move_plugins {
    local backup name
    backup="$NEOVIM_PLUGINS-failed.$(date +%Y%m%d%H%M%S)"
    for name in "$@"; do
        # Can be parsed from the output, it must be a plain directory name below lazy
        if [[ ! "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] || [ ! -d "$NEOVIM_PLUGINS/$name" ] || [ -L "$NEOVIM_PLUGINS/$name" ]; then
            continue
        fi
        mkdir -p "$backup"
        mv -- "$NEOVIM_PLUGINS/$name" "$backup/$name"
        note "Installed the neovim plugin $name again, the failed copy is in $backup"
    done
}

# Install the plugins. The first run only bootstraps the plugin manager and may report
# errors, so only a plugin that fails again gets replaced.
function _neovim_sync {
    local attempt names log="$TMPDIR/neovim-sync.log" lock="$HOME/.config/nvim/lazy-lock.json"
    local saved="$TMPDIR/lazy-lock.json"
    if [ -f "$lock" ]; then
        cp "$lock" "$saved"
    fi
    for attempt in 1 2 3; do
        # shellcheck disable=SC2046 # one plain directory name per line
        _neovim_move_plugins $(_neovim_damaged_plugins)
        if nvim_headless -c 'SyncInstall' -c qall 2>&1 | tee "$log"; then
            if [ -z "$(_neovim_damaged_plugins)" ]; then
                return 0
            fi
        else
            # A failed sync drops the missing plugins from the lockfile and the next one
            # pins them at their latest commit: go back to the versions from before
            if [ -f "$saved" ]; then
                cp "$saved" "$lock"
            fi
            if [ "$attempt" -ge 2 ]; then
                names="$(sed -n 's/.*installing these plugins failed: //p' "$log" | tail -n 1)"
                # shellcheck disable=SC2086 # the names are split on purpose
                _neovim_move_plugins ${names//,/ }
            fi
        fi
    done
    return 1
}

function _neovim_setup {
    _neovim_config
    if ! nvim_usable; then
        note "Installed neovim is older than 0.12, skipped the plugin sync. Use the upstream release."
        return 0
    fi
    if ! command -v tree-sitter >/dev/null 2>&1; then
        cargo_install --locked tree-sitter-cli
    fi
    add_command_to_path tree-sitter
    _neovim_sync
    nvim_mason lua-language-server
    nvim_mason python-lsp-server
}

function neovim_install_arch {
    _neovim_setup
}

function neovim_install_debian {
    if use_upstream neovim; then
        _neovim_upstream
    else
        pkg_install neovim
    fi
    _neovim_setup
}
