#!/bin/bash
# shellcheck disable=SC2034 # color codes are used by the sourcing scripts

set -o pipefail

LOG_FILE="$(mktemp)"

# Remote location of the repository and local checkout root (used if DEBUG is set)
REPO_URL="${ENV_SETUP_URL:-https://raw.githubusercontent.com/TumbleOwlee/env-setup/main}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Color codes
NONE="\e[0m"
BLACK="\e[30m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
PURPLE="\e[35m"
CYAN="\e[36m"

trap "exit 1" SIGINT

# Print info
function info {
    echo -e "[${CYAN}+${NONE}] $*"
    echo -e "[+] $*" >>"$LOG_FILE"
}

# Print notify
function notify {
    echo -e "  [${GREEN}!${NONE}] $*"
    echo -e "  [!] $*" >>"$LOG_FILE"
}

# Ask for input
function ask {
    echo -e -n "[${YELLOW}?${NONE}] $1 " 1>&2
    echo -e -n "[?] $1 " >>"$LOG_FILE"

    if [ "_$NO_CONFIRM" != "_" ]; then
        echo "$2"
        echo "$2" 1>&2
        echo "$2" >>"$LOG_FILE"
    else
        read -r value
        echo "$value" >>"$LOG_FILE"
        if [ "_$value" == "_" ]; then
            echo "$2"
            echo "$2" >>"$LOG_FILE"
        else
            echo "$value"
            echo "$value" >>"$LOG_FILE"
        fi
    fi
}

# Ask for retry
function retry {
    echo -e -n "[${RED}!${NONE}] Failed. Show additional log? [y/N] " 1>&2
    echo -e -n "[!] Failed. Show additional log? [y/N] " >>"$LOG_FILE"

    if [ "_$NO_CONFIRM" != "_" ]; then
        echo "N" 1>&2
        echo "N" >>"$LOG_FILE"
        tail -n 40 "$LOG_FILE"
        false
    else
        read -r value1
        echo "$value1" >>"$LOG_FILE"
        if [ "_$value1" == "_y" ] || [ "_$value1" == "_Y" ]; then
            less "$LOG_FILE"
        fi
        echo -e -n "[${RED}?${NONE}] Retry? [Y/n] " 1>&2
        echo -e -n "[?] Retry? [Y/n] " >>"$LOG_FILE"
        read -r value2
        echo "$value2" >>"$LOG_FILE"
        if [ "_$value2" == "_n" ] || [ "_$value2" == "_N" ]; then
            false
        else
            true
        fi
    fi
}

# Ask for termination
function terminate {
    echo -e -n "[${RED}?${NONE}] Terminate? [Y/n] " 1>&2
    echo -e -n "[?] Terminate? [Y/n] " >>"$LOG_FILE"

    if [ "_$NO_CONFIRM" != "_" ]; then
        exit 1
    fi

    read -r value
    echo "$value" >>"$LOG_FILE"
    if [ "_$value" == "_n" ] || [ "_$value" == "_N" ]; then
        false
    else
        exit 1
    fi
}

# Warn the user
function warn {
    echo -e "[${RED}!${NONE}] $*"
    echo -e "[!] $*" >>"$LOG_FILE"
}

# Report error
function error {
    echo -e "[${RED}!${NONE}] $*"
    echo -e "[!] $*" >>"$LOG_FILE"
}

# Execute a command in a subshell. Honors STDOUT, STDERR (cout/cerr = terminal)
# and the PIPE array. Arguments: $1 = working dir, rest = command.
function _exec_cmd {
    local dir="$1"
    shift
    (
        cd "$dir" || exit 1
        [ "_$STDOUT" == "_cout" ] || exec >>"$STDOUT"
        [ "_$STDERR" == "_cerr" ] || exec 2>>"$STDERR"
        if [ ${#PIPE[@]} -gt 0 ]; then
            "$@" | "${PIPE[@]}"
        else
            "$@"
        fi
    )
}

# Run a command, ask to retry on failure
function run_with_retry {
    local dir="${DIR:-$(pwd)}"
    local exitcode=0
    STDOUT="${STDOUT:-$LOG_FILE}"
    STDERR="${STDERR:-$LOG_FILE}"

    while true; do
        notify "Execute '${CYAN}$*${NONE}'"
        _exec_cmd "$dir" "$@" &
        local pid=$!
        (
            secs=0
            while sleep 1; do
                secs=$((secs + 1))
                echo -en "\r      Progress: ${YELLOW}${secs}s${NONE}     "
            done
        ) &
        local ticker=$!
        wait "$pid"
        exitcode=$?
        kill "$ticker" 2>/dev/null
        wait "$ticker" 2>/dev/null
        echo -en "\r"
        [ "$exitcode" -eq 0 ] && break || retry || terminate || break
    done

    unset PIPE
    unset STDOUT
    unset STDERR
    return "$exitcode"
}

# Run a command once
function run_once {
    local dir="${DIR:-$(pwd)}"
    local exitcode=0
    STDOUT="${STDOUT:-$LOG_FILE}"
    STDERR="${STDERR:-$LOG_FILE}"

    notify "Execute '${CYAN}$*${NONE}'"
    _exec_cmd "$dir" "$@" || exitcode=$?

    unset PIPE
    unset STDOUT
    unset STDERR
    return "$exitcode"
}

# Return 0 if nvim exists and is new enough for the neovim configuration (>= 0.12).
# An older nvim makes the config abort at "Press any key" and hang headless runs.
function nvim_usable {
    command -v nvim >/dev/null 2>&1 &&
        nvim --clean --headless -c 'if has("nvim-0.12") | qall | else | cquit | endif' </dev/null >/dev/null 2>&1
}

# Install neovim LSP
function nvim_install_lsp {
    if nvim_usable; then
        run_with_retry nvim --headless -c "MasonInstall $1" -c "quitall"
    fi
}

# Check for proxy
function check_proxy {
    local resp
    resp=$(ask "Behind a proxy? [y/N]" "N")
    if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
        local missing=0
        if [ "_${http_proxy:-}" == "_" ]; then
            missing=1
            error "Environment '${RED}\$http_proxy${NONE}' is empty!"
        else
            info "Environment '\$http_proxy' is '$http_proxy'"
        fi
        if [ "_${https_proxy:-}" == "_" ]; then
            missing=1
            error "Environment '${RED}\$https_proxy${NONE}' is empty!"
        else
            info "Environment '\$https_proxy' is '$https_proxy'"
        fi
        if [ "$missing" -eq 1 ]; then
            error "${RED}Fill missing proxy environment variables.${NONE}"
            exit 1
        fi
    fi
}

# Stop the background sudo keep-alive loop
function _sudo_cleanup {
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
        SUDO_KEEPALIVE_PID=""
    fi
}

# Check for sudo, set $SUDO and keep the credentials fresh
function check_sudo {
    info "Check for root privileges.."
    if [ "$(id -u)" -eq 0 ]; then
        export SUDO=''
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        error "You aren't root and sudo isn't installed."
        exit 1
    fi
    export SUDO=sudo
    sudo -v || exit 1
    local parent=$$
    (
        while true; do
            sudo -n -v
            sleep 60
            kill -0 "$parent" 2>/dev/null || exit 0
        done
    ) >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
    trap _sudo_cleanup EXIT
    trap '_sudo_cleanup; exit 1' INT
}

# Copy/download one repo file to dest atomically (never leaves partial files)
function _fetch_once {
    local path="$1" dest="$2" tmp
    tmp="$(mktemp)" || return 1
    if [ -n "$DEBUG" ]; then
        cp "$REPO_ROOT/$path" "$tmp"
    else
        curl -fsSL "$REPO_URL/$path" -o "$tmp"
    fi || {
        rm -f "$tmp"
        return 1
    }
    mv "$tmp" "$dest" || {
        rm -f "$tmp"
        return 1
    }
}

# Fetch a file of the repository: fetch <repo-path> <dest>
function fetch {
    run_with_retry _fetch_once "$1" "$2"
}

# Fetch a repository file and source it: source_remote <repo-path>
function source_remote {
    local tmp
    tmp="$(mktemp)" || exit 1
    if ! fetch "$1" "$tmp" || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        error "Failed to fetch '$1'."
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$tmp"
    rm -f "$tmp"
}

# Detect the distribution family: echoes arch|debian
function detect_distro {
    local file="${OS_RELEASE_FILE:-/etc/os-release}" id="" id_like="" d
    [ -r "$file" ] || return 1
    id="$(sed -n 's/^ID=//p' "$file" | head -n 1 | tr -d '"'"'"'')"
    id_like="$(sed -n 's/^ID_LIKE=//p' "$file" | head -n 1 | tr -d '"'"'"'')"
    for d in $id $id_like; do
        case "$d" in
        arch)
            echo arch
            return 0
            ;;
        debian | ubuntu)
            echo debian
            return 0
            ;;
        esac
    done
    return 1
}

# Map a logical package name to the distro specific name
function pkg_name {
    local distro="${DISTRO:-$(detect_distro)}" arch deb
    case "$1" in
    ninja) arch=ninja deb=ninja-build ;;
    fd) arch=fd deb=fd-find ;;
    python) arch=python deb=python3 ;;
    pipx) arch=python-pipx deb=pipx ;;
    docker) arch=docker deb=docker.io ;;
    compose)
        arch=docker-compose deb=docker-compose-v2
        if [ "$distro" == "debian" ] && ! apt-cache show docker-compose-v2 >/dev/null 2>&1; then
            deb=docker-compose
        fi
        ;;
    delta) arch=git-delta deb=git-delta ;;
    libclang) arch=clang deb=libclang-dev ;;
    *) arch="$1" deb="$1" ;; # fontconfig, gettext, ...
    esac
    case "$distro" in
    arch) echo "$arch" ;;
    debian) echo "$deb" ;;
    *) return 1 ;;
    esac
}

# Install logical packages: pkg_install <logical>...
function pkg_install {
    local distro names=() n
    distro="${DISTRO:-$(detect_distro)}" || return 1
    for n in "$@"; do
        names+=("$(pkg_name "$n")") || return 1
    done
    local sudo=()
    [ -n "$SUDO" ] && sudo=("$SUDO")
    if [ "$distro" == "arch" ]; then
        # yay refuses to run as root; all packages are in the official repos
        if command -v yay >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
            run_with_retry yay -S --needed --noconfirm "${names[@]}"
        else
            run_with_retry "${sudo[@]}" pacman -S --needed --noconfirm "${names[@]}"
        fi
    else
        run_with_retry "${sudo[@]}" apt-get install -y "${names[@]}"
    fi
}

# Check if a logical package is installed
function pkg_installed {
    local distro name
    distro="${DISTRO:-$(detect_distro)}" || return 1
    name="$(pkg_name "$1")" || return 1
    if [ "$distro" == "arch" ]; then
        pacman -Qi "$name" >/dev/null 2>&1
    else
        dpkg-query -W -f='${Status}' "$name" 2>/dev/null | grep -q "install ok installed"
    fi
}

# Print the packaged (repository) version of a logical package
function pkg_version {
    local distro name ver
    distro="${DISTRO:-$(detect_distro)}" || return 1
    name="$(pkg_name "$1")" || return 1
    if [ "$distro" == "arch" ]; then
        ver="$(pacman -Si "$name" 2>/dev/null | awk '/^Version/ {print $3; exit}')"
    else
        ver="$(apt-cache policy "$name" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
        [ "$ver" == "(none)" ] && ver=""
    fi
    [ -n "$ver" ] || return 1
    echo "$ver"
}

# Ask whether to use the upstream release; returns 0 for upstream
function choose_source {
    local resp
    resp=$(ask "Use upstream release instead of packaged $1 $2? [y/N]" "N")
    [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]
}

# Append a line to a file unless present
function ensure_line {
    grep -qxF -- "$2" "$1" 2>/dev/null || echo "$2" >>"$1"
}

# Copy a file to <path>.bak.<timestamp> if it exists
function backup_file {
    [ -e "$1" ] || return 0
    cp -a "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"
}

# Remove the blocks appended by the legacy setup scripts
function migrate_legacy_blocks {
    local f tmp
    for f in "$HOME/.bashrc" "$HOME/.config/fish/config.fish"; do
        [ -f "$f" ] || continue
        tmp="$(mktemp)"
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
            notify "Removed legacy blocks from ${CYAN}$f${NONE}"
        fi
        rm -f "$tmp"
    done
}

function delete_log {
    if [ -f "$LOG_FILE" ]; then
        rm -rf "$LOG_FILE"
    fi
}

# Initialize log
touch "$LOG_FILE"
info "Logging into ${LOG_FILE}."
