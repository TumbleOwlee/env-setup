#!/bin/bash
# The API for modules: commands, packages, files and upstream sources. Module
# functions run in a background subshell with 'set -e', all output in the log and
# no stdin, so they can neither prompt nor change the state of the engine.

# Run a command and show it in the status line and the log
function run {
    printf '$ %s\n' "$*"
    printf '%s' "$*" >"$STATE_FILE"
    "$@"
}

# Run a command as root. sudo -n never prompts, the credentials are kept fresh by main.sh.
function root {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        # sudo drops the proxy settings from the environment
        sudo -n env ${http_proxy:+http_proxy="$http_proxy"} ${https_proxy:+https_proxy="$https_proxy"} \
            ${no_proxy:+no_proxy="$no_proxy"} "$@"
    fi
}

# Add a line to the summary printed at the end of the run
function note {
    printf '%s\n' "$*" >>"$NOTES_FILE"
}

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------

# Map a logical package name to the distro specific name
function pkg_name {
    local arch="$1" deb="$1"
    case "$1" in
    ninja) deb=ninja-build ;;
    fd) deb=fd-find ;;
    python) deb=python3 ;;
    pipx) arch=python-pipx ;;
    docker) deb=docker.io ;;
    compose)
        arch=docker-compose deb=docker-compose-v2
        if [ "$DISTRO" == "debian" ] && ! apt-cache show docker-compose-v2 >/dev/null 2>&1; then
            deb=docker-compose
        fi
        ;;
    delta) arch=git-delta ;;
    pkg-config) arch=pkgconf ;;
    libclang) arch=clang deb=libclang-dev ;;
    esac
    if [ "$DISTRO" == "arch" ]; then
        echo "$arch"
    else
        echo "$deb"
    fi
}

# apt-get that never asks and waits for other package managers, e.g. unattended upgrades
function apt_get {
    printf '$ apt-get %s\n' "$*"
    printf 'apt-get %s' "$*" >"$STATE_FILE"
    root env DEBIAN_FRONTEND=noninteractive apt-get -y -o DPkg::Lock::Timeout=300 \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

# Refresh the package lists once per run. Arch only syncs a missing database, and never
# without upgrading: installing after a plain 'pacman -Sy' is a partial upgrade, which
# breaks tools like curl. An existing database is used as is, unless the upgrade module ran.
function pkg_sync {
    if [ -e "$WORK/pkg-synced" ]; then
        return 0
    fi
    if [ "$DISTRO" == "debian" ]; then
        apt_get update
    elif ! compgen -G '/var/lib/pacman/sync/*.db' >/dev/null; then
        run root pacman -Syu --noconfirm
    fi
    touch "$WORK/pkg-synced"
}

# Install logical packages: pkg_install <logical>...
function pkg_install {
    local names=() n recommends=()
    pkg_sync
    for n in "$@"; do
        names+=("$(pkg_name "$n")")
    done
    if [ "$DISTRO" == "arch" ]; then
        run root pacman -S --needed --noconfirm "${names[@]}"
    else
        if [ -n "$MINIMAL" ]; then
            recommends=(--no-install-recommends)
        fi
        apt_get install "${recommends[@]}" "${names[@]}"
    fi
}

# Print the packaged version of a logical package, fail if there is no such package
function pkg_version {
    local name ver
    name="$(pkg_name "$1")"
    if [ "$DISTRO" == "arch" ]; then
        ver="$(pacman -Si "$name" 2>/dev/null | awk '/^Version/ {print $3; exit}')"
    else
        ver="$(apt-cache policy "$name" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
        if [ "$ver" == "(none)" ]; then
            ver=""
        fi
    fi
    [ -n "$ver" ] && echo "$ver"
}

# Print the tag of the latest release without the rate limited API: github_latest_tag <owner/repo>
function github_latest_tag {
    local url
    url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' --connect-timeout 10 -m 30 "https://github.com/$1/releases/latest")" || return 1
    url="${url##*/}"
    [ -n "$url" ] && [ "$url" != "latest" ] && echo "$url"
}

# ---------------------------------------------------------------------------
# Upstream or package
# ---------------------------------------------------------------------------

declare -A UPSTREAM

# Call from <module>_prepare. Upstream is the default, also if there is no package:
# choose_upstream <tool> <logical-pkg>
function choose_upstream {
    local ver
    UPSTREAM["$1"]=1
    if [ -z "$INTERACTIVE" ]; then
        return 0
    fi
    ver="$(pkg_version "$2")" || return 0
    if ! confirm "Use upstream release of $1 instead of the package $ver? [Y/n]" Y; then
        UPSTREAM["$1"]=""
    fi
}

function use_upstream {
    [ -n "${UPSTREAM[$1]:-}" ]
}

# Download a file: download <url> <dest>
function download {
    mkdir -p "$(dirname "$2")"
    run curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$1" -o "$2.tmp"
    mv "$2.tmp" "$2"
}

# Download an installer script and execute it: run_installer <url> [args]
function run_installer {
    local url="$1" script="$TMPDIR/installer-$RANDOM.sh"
    shift
    download "$url" "$script"
    run sh "$script" "$@"
}

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

# Copy a file to <path>.bak.<timestamp> if it exists
function backup_file {
    if [ -e "$1" ]; then
        cp -a "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"
    fi
}

# Append a line to a file unless present
function ensure_line {
    if ! grep -qxF -- "$2" "$1" 2>/dev/null; then
        echo "$2" >>"$1"
    fi
}

# Directories that new shells add to PATH, one per line. Read by the snippets of
# the base and fish modules, so a module only registers what it installs into.
PATHS_FILE="$HOME/.config/dotstrap/paths"

# Add a directory to PATH of new shells: add_to_path <dir>
function add_to_path {
    mkdir -p "$(dirname "$PATHS_FILE")"
    ensure_line "$PATHS_FILE" "$1"
}

# This project was called env-setup. Move its configuration directory. The link stays,
# since files installed by modules that are not part of this run still use the old path.
function migrate_config_dir {
    local old="$HOME/.config/env-setup" new="$HOME/.config/dotstrap"
    if [ -L "$old" ] || [ ! -d "$old" ]; then
        return 0
    fi
    if [ -e "$new" ]; then
        note "Both $old and $new exist. Move what you still need by hand, the old one is not used anymore."
        return 0
    fi
    mv -- "$old" "$new"
    ln -s dotstrap "$old"
}

# Update the line of a shell startup file that sources the old snippet, in place so that
# it keeps its position: migrate_source_line <file>
function migrate_source_line {
    local tmp="$TMPDIR/source-line-$RANDOM"
    local old='[ -f ~/.config/env-setup/bashrc.sh ] && . ~/.config/env-setup/bashrc.sh'
    local new='[ -f ~/.config/dotstrap/bashrc.sh ] && . ~/.config/dotstrap/bashrc.sh'
    if ! grep -qxF -- "$old" "$1" 2>/dev/null; then
        return 0
    fi
    awk -v old="$old" -v new="$new" '$0 == old { print new; next } { print }' "$1" >"$tmp"
    backup_file "$1"
    cat "$tmp" >"$1"
}

# Add the directory of a command to PATH if it's inside the home directory, e.g. a
# tool installed into ~/.local/bin instead of a package: add_command_to_path <cmd>
function add_command_to_path {
    local p
    p="$(command -v "$1")" || return 0
    case "$p" in
    "$HOME"/*) add_to_path "$(dirname "$p")" ;;
    esac
}

# Write stdin to <dest> only if the content differs (keeps the file untouched otherwise).
# The temporary file goes away with the work directory, like everything in TMPDIR.
function write_owned {
    local tmp="$TMPDIR/owned-$RANDOM"
    cat >"$tmp"
    mkdir -p "$(dirname "$1")"
    if ! cmp -s "$tmp" "$1"; then
        cat "$tmp" >"$1"
    fi
}

# Install a file of Unix/: put <repo-path> <dest> <mode> [backup]
# Skips if identical, backs up a differing existing file when 'backup' is given.
function put {
    local src="$ROOT/$1" dest="$2" mode="$3" backup="${4:-}"
    mkdir -p "$(dirname "$dest")"
    if ! cmp -s "$src" "$dest"; then
        if [ "$backup" == "backup" ]; then
            backup_file "$dest"
        fi
        cp "$src" "$dest"
    fi
    chmod "$mode" "$dest"
}

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

# cargo with its registry in the work directory, so that it's removed after the run
function cargo_cached {
    run env CARGO_HOME="$WORK/cargo" cargo "$@"
}

# Install a cargo tool into ~/.cargo/bin
function cargo_install {
    add_to_path "$HOME/.cargo/bin"
    cargo_cached install --root "$HOME/.cargo" "$@"
}

# Return 0 if nvim exists and is new enough for the neovim configuration (>= 0.12).
# An older nvim makes the config abort at "Press any key" and hang headless runs.
function nvim_usable {
    command -v nvim >/dev/null 2>&1 &&
        nvim --clean --headless -c 'if has("nvim-0.12") | qall | else | cquit | endif' </dev/null >/dev/null 2>&1
}

# Headless nvim with a time limit: the configuration must not be able to hang the run
function nvim_headless {
    run timeout 900 nvim --headless "$@"
}

# Install a language server if neovim is available
function nvim_mason {
    if nvim_usable; then
        nvim_headless -c "MasonInstall $1" -c quitall
    fi
}
