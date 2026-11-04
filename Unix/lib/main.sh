#!/bin/bash
# shellcheck disable=SC2034 # the settings are used by the modules
# The engine: parse the flags, load the modules, resolve the plan, ask everything up
# front and then run unattended. Started by Unix/setup.sh.

set -o pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES_DIR="${ENV_SETUP_MODULES:-$ROOT/modules}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/env-setup"
KEEP_LOGS=5

# shellcheck source=Unix/lib/ui.sh
source "$ROOT/lib/ui.sh"
# shellcheck source=Unix/lib/menu.sh
source "$ROOT/lib/menu.sh"
# shellcheck source=Unix/lib/helpers.sh
source "$ROOT/lib/helpers.sh"

NO_CONFIRM="" MINIMAL="" DRY_RUN="" VERBOSE="" INTERACTIVE="" LIST="" SHOW_LOG=""
LOG_FILE=/dev/null STATE_FILE=/dev/null NOTES_FILE=/dev/null WORK="" TAIL_PID="" KEEPALIVE_PID=""
declare -A SKIP=() INCLUDE=() ONLY=()

# Module registry
M_NAMES=()
declare -A M_DESC=() M_DEPS=() M_AFTER=() M_PKGS=() M_DISTROS=() M_FLAGS=()
# Plan and results
declare -A WANT=() VISITED=() RESULT=() ANSWER=()
ORDER=()

function usage {
    cat <<EOF
Usage: setup.sh [flags]

  -n, --noconfirm    Answer every question with its default. Implied without a terminal.
  -v, --verbose      Print the command output instead of the status line.
      --skip=A,B     Don't install these modules.
      --include=A,B  Install these modules, even if off by default or left out by --minimal.
      --only=A,B     Install only these modules and what they depend on.
      --minimal      Smallest result: fewer modules, no docs or recommended packages,
                     package caches are wiped. Meant for images.
      --dry-run      Print the plan and exit. Changes nothing.
      --list         List the modules and exit.
      --log          Show the log of the last run and exit.
  -h, --help         Show this help.
EOF
}

# Add comma separated names to an associative array: _add_names <array> <names>
function _add_names {
    local -n target="$1"
    local name names
    IFS=, read -ra names <<<"$2"
    for name in "${names[@]}"; do
        target["$name"]=1
    done
}

function parse_args {
    local arg
    for arg in "$@"; do
        case "$arg" in
        -n | --noconfirm) NO_CONFIRM=1 ;;
        -v | --verbose) VERBOSE=1 ;;
        --minimal) MINIMAL=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --list) LIST=1 ;;
        --log) SHOW_LOG=1 ;;
        --skip=*) _add_names SKIP "${arg#*=}" ;;
        --include=*) _add_names INCLUDE "${arg#*=}" ;;
        --only=*) _add_names ONLY "${arg#*=}" ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "Unknown flag '$arg'."
            ;;
        esac
    done
}

# Set DISTRO to the distribution family
function detect_distro {
    local file="${OS_RELEASE_FILE:-/etc/os-release}" d
    [ -r "$file" ] || die "Can't read $file."
    # shellcheck disable=SC1090 # os-release is defined to be shell compatible
    for d in $(. "$file" && echo "${ID:-} ${ID_LIKE:-}"); do
        case "$d" in
        arch)
            DISTRO=arch
            return 0
            ;;
        debian | ubuntu)
            DISTRO=debian
            return 0
            ;;
        esac
    done
    die "Unsupported distribution (supported: Arch, Debian/Ubuntu)."
}

# Register a module. Options ending in -arch or -debian only count on that distro.
#   --desc TEXT       Shown in the module list and --list
#   --packages LIST   Logical packages installed before <name>_install
#   --deps LIST       Modules that must be installed first
#   --after LIST      Run after these modules if they are installed too
#   --distros LIST    Only available on these distros
#   --required        Can't be skipped
#   --core            Runs before all modules without this flag
#   --internal        Never asked for, only installed as a dependency
#   --optional        Off by default
#   --no-minimal      Left out by --minimal
# Functions, all optional, '-' in the name becomes '_':
#   <name>_prepare             Ask questions, runs before anything is installed
#   <name>_install             Install, must be safe to run again
#   <name>_install_<distro>    Used instead of <name>_install on that distro
function module {
    local name="$1" key
    shift
    M_NAMES+=("$name")
    while [ $# -gt 0 ]; do
        case "$1" in
        --desc)
            M_DESC["$name"]="$2"
            shift 2
            ;;
        --packages | --packages-* | --deps | --deps-* | --after | --distros)
            key="${1#--}"
            if [ "$key" == "${key%-*}" ] || [ "${key##*-}" == "$DISTRO" ]; then
                case "$key" in
                packages*) M_PKGS["$name"]+=" $2" ;;
                deps*) M_DEPS["$name"]+=" $2" ;;
                after) M_AFTER["$name"]+=" $2" ;;
                distros) M_DISTROS["$name"]+=" $2" ;;
                esac
            fi
            shift 2
            ;;
        --required | --core | --internal | --optional | --no-minimal)
            M_FLAGS["$name"]+=" ${1#--} "
            shift
            ;;
        *) die "Module '$name': unknown option '$1'." ;;
        esac
    done
}

function has_flag {
    [[ "${M_FLAGS[$1]:-}" == *" $2 "* ]]
}

function available {
    [ -z "${M_DISTROS[$1]:-}" ] || [[ " ${M_DISTROS[$1]} " == *" $DISTRO "* ]]
}

function is_module {
    [[ " ${M_NAMES[*]} " == *" $1 "* ]]
}

function load_modules {
    local f
    for f in "$MODULES_DIR"/*.sh; do
        # shellcheck disable=SC1090
        source "$f"
    done
}

function validate_names {
    local list name
    for list in SKIP INCLUDE ONLY; do
        # shellcheck disable=SC2178 # a nameref to the associative array
        local -n names="$list"
        for name in "${!names[@]}"; do
            if ! is_module "$name" || has_flag "$name" internal; then
                die "Unknown module '$name'. See --list."
            fi
            if ! available "$name" && [ "$list" != "SKIP" ]; then
                die "Module '$name' is not available on $DISTRO."
            fi
            if [ "$list" == "SKIP" ] && has_flag "$name" required; then
                die "Module '$name' is required and can't be skipped."
            fi
        done
        unset -n names
    done
}

# Add the dependencies of everything in an array to it
function _close_over_deps {
    local -n set="$1"
    local name dep changed=1
    while [ -n "$changed" ]; do
        changed=""
        for name in "${!set[@]}"; do
            for dep in ${M_DEPS[$name]:-}; do
                if [ -z "${set[$dep]:-}" ]; then
                    set["$dep"]=1
                    changed=1
                fi
            done
        done
    done
}

# Return 0 unless the distro or the flags rule out the module
function _allowed {
    local name="$1"
    available "$name" || return 1
    has_flag "$name" required && return 0
    [ -z "${SKIP[$name]:-}" ] || return 1
    if [ ${#ONLY[@]} -gt 0 ] && [ -z "${ONLY[$name]:-}" ]; then
        return 1
    fi
    if [ -n "$MINIMAL" ] && has_flag "$name" no-minimal && [ -z "${INCLUDE[$name]:-}" ]; then
        return 1
    fi
}

# Return 0 if neither the module nor one of its dependencies is ruled out
function _installable {
    local dep
    _allowed "$1" || return 1
    for dep in ${M_DEPS[$1]:-}; do
        has_flag "$dep" internal && continue
        _installable "$dep" || return 1
    done
}

# Let the user select from the modules that are still open: sets ANSWER[name]=1 or 0.
# Without a terminal or with --only nothing is asked. What a selected module depends on
# is selected too, so that a dependency that was switched off doesn't leave it out.
function choose_modules {
    local name i names=() chosen=()
    local -A picked=()
    if [ -z "$INTERACTIVE" ] || [ ${#ONLY[@]} -gt 0 ]; then
        return 0
    fi
    LABELS=() HINTS=() CHECKED=()
    for name in "${M_NAMES[@]}"; do
        if has_flag "$name" internal || has_flag "$name" required || [ -n "${INCLUDE[$name]:-}" ]; then
            continue
        fi
        _installable "$name" || continue
        names+=("$name")
        LABELS+=("$(printf '%-11s' "$name")")
        HINTS+=("${M_DESC[$name]:-}")
        if has_flag "$name" optional; then
            CHECKED+=(0)
        else
            CHECKED+=(1)
        fi
    done
    [ ${#names[@]} -gt 0 ] || return 0
    _menu multi "Modules" "(space toggles, a all, enter, q aborts; dependencies are added)"
    for ((i = 0; i < ${#names[@]}; i++)); do
        if [ "${CHECKED[i]}" == 1 ]; then
            picked["${names[i]}"]=1
        fi
    done
    _close_over_deps picked
    for name in "${names[@]}"; do
        ANSWER["$name"]="${picked[$name]:-0}"
        if [ "${ANSWER[$name]}" == 1 ]; then
            chosen+=("$name")
        fi
    done
    _answered "Modules" "${chosen[*]:-none of them}"
    printf '[?] Modules: %s\n' "${chosen[*]:-none of them}" >>"$LOG_FILE"
}

# Decide about one module, its dependencies first: WANT[name]=1 or 0
function decide {
    local name="$1" dep
    [ -z "${WANT[$name]:-}" ] || return 0
    WANT["$name"]=0
    _allowed "$name" || return 0
    # Switched off in the list: nothing to say about its dependencies
    [ "${ANSWER[$name]:-}" != 0 ] || return 0
    for dep in ${M_DEPS[$name]:-}; do
        has_flag "$dep" internal && continue
        decide "$dep"
        if [ "${WANT[$dep]}" != "1" ]; then
            warn "Leaving out $name, it needs $dep."
            return 0
        fi
    done
    if has_flag "$name" required || [ ${#ONLY[@]} -gt 0 ] || [ -n "${INCLUDE[$name]:-}" ]; then
        WANT["$name"]=1
        return 0
    fi
    # Selected in the list, or nothing was asked and the default applies
    if [ -n "${ANSWER[$name]:-}" ] || ! has_flag "$name" optional; then
        WANT["$name"]=1
    fi
}

# Dependencies and soft ordering first, depth first
function _visit {
    local name="$1" other
    [ -z "${VISITED[$name]:-}" ] || return 0
    VISITED["$name"]=1
    for other in ${M_DEPS[$name]:-} ${M_AFTER[$name]:-}; do
        if [ "${WANT[$other]:-}" == "1" ]; then
            _visit "$other"
        fi
    done
    ORDER+=("$name")
}

function resolve_plan {
    local name dep changed=1
    _close_over_deps INCLUDE
    _close_over_deps ONLY
    choose_modules
    for name in "${M_NAMES[@]}"; do
        has_flag "$name" internal || decide "$name"
    done
    # Internal modules are only installed for a module that needs them
    while [ -n "$changed" ]; do
        changed=""
        for name in "${M_NAMES[@]}"; do
            [ "${WANT[$name]:-}" == "1" ] || continue
            for dep in ${M_DEPS[$name]:-}; do
                if [ "${WANT[$dep]:-}" != "1" ]; then
                    WANT["$dep"]=1
                    changed=1
                fi
            done
        done
    done
    for name in "${M_NAMES[@]}"; do
        if has_flag "$name" core && [ "${WANT[$name]:-}" == "1" ]; then
            _visit "$name"
        fi
    done
    for name in "${M_NAMES[@]}"; do
        if [ "${WANT[$name]:-}" == "1" ]; then
            _visit "$name"
        fi
    done
}

function print_list {
    local name kind
    for name in "${M_NAMES[@]}"; do
        has_flag "$name" internal && continue
        available "$name" || continue
        kind=""
        has_flag "$name" required && kind+=" (required)"
        has_flag "$name" optional && kind+=" (off by default)"
        has_flag "$name" no-minimal && kind+=" (not with --minimal)"
        printf '%-12s %s%s\n' "$name" "${M_DESC[$name]:-}" "$kind"
    done
}

function print_plan {
    local name i=0
    for name in "${ORDER[@]}"; do
        i=$((i + 1))
        printf '%3d. %-12s %s\n' "$i" "$name" "${M_PKGS[$name]:+packages:${M_PKGS[$name]}}"
    done
}

function show_last_log {
    local logs=("$LOG_DIR"/*.log)
    [ -e "${logs[0]}" ] || die "No log found in $LOG_DIR."
    LOG_FILE="${logs[-1]}"
    show_log
}

function init_run {
    local stamp logs i
    WORK="$(mktemp -d /var/tmp/env-setup.XXXXXX 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/env-setup.XXXXXX")" ||
        die "Can't create a work directory."
    mkdir -p "$WORK/tmp" "$WORK/cache" "$WORK/cargo"
    STATE_FILE="$WORK/state"
    NOTES_FILE="$WORK/notes"
    : >"$STATE_FILE"
    : >"$NOTES_FILE"
    trap cleanup EXIT
    trap 'on_signal 130' INT
    trap 'on_signal 143' TERM HUP

    # Everything the tools cache or build goes into the work directory and is removed
    # with it. Caches of the user that existed before the run stay untouched.
    export TMPDIR="$WORK/tmp" XDG_CACHE_HOME="$WORK/cache"
    export GIT_TERMINAL_PROMPT=0

    stamp="$(date +%Y%m%d-%H%M%S)"
    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        LOG_FILE="$LOG_DIR/$stamp.log"
        # Only files named like our logs, sorted by time through their names
        logs=("$LOG_DIR"/????????-??????.log)
        for ((i = 0; i < ${#logs[@]} - KEEP_LOGS + 1; i++)); do
            if [ -f "${logs[$i]}" ]; then
                rm -f -- "${logs[$i]}"
            fi
        done
    else
        LOG_FILE="$WORK/run.log"
    fi
    : >"$LOG_FILE"
    if [ -n "$VERBOSE" ]; then
        tail -n 0 -f "$LOG_FILE" &
        TAIL_PID=$!
    fi
}

function on_signal {
    stop_child
    printf '\n'
    error "Interrupted. Log: $LOG_FILE"
    exit "$1"
}

# Delete the work directory, and nothing but a directory named like one created by init_run
function _remove_work {
    case "$WORK" in
    */env-setup.??????) ;;
    *) return 0 ;;
    esac
    if [ -d "$WORK" ] && [ ! -L "$WORK" ]; then
        # Module caches can contain read-only directories
        chmod -R u+w -- "$WORK" 2>/dev/null
        rm -rf -- "$WORK"
    fi
}

function cleanup {
    local rc=$?
    menu_restore
    stop_child
    if [ -n "$TAIL_PID" ]; then
        sleep 0.2
        kill "$TAIL_PID" 2>/dev/null
    fi
    if [ -n "$KEEPALIVE_PID" ]; then
        kill "$KEEPALIVE_PID" 2>/dev/null
    fi
    _remove_work
    if [ -n "$MINIMAL" ] && [ "$rc" -eq 0 ] && [ -f "$LOG_FILE" ]; then
        rm -f -- "$LOG_FILE"
        # Only if empty, the parents are not ours
        rmdir -- "$LOG_DIR" 2>/dev/null
    fi
    exit "$rc"
}

# Check for root or sudo and keep the sudo credentials fresh
function check_root {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    command -v sudo >/dev/null 2>&1 || die "You aren't root and sudo isn't installed."
    if [ -n "$INTERACTIVE" ]; then
        # shellcheck disable=SC2024 # the redirects are for sudo's prompt
        sudo -v </dev/tty >/dev/tty 2>&1 || die "sudo failed."
    else
        sudo -n true 2>/dev/null || die "sudo needs a password, but there is no terminal to ask for it."
    fi
    (
        while sleep 60; do
            kill -0 $$ 2>/dev/null || exit 0
            sudo -n -v
        done
    ) >/dev/null 2>&1 </dev/null &
    KEEPALIVE_PID=$!
}

function _hook {
    local fn="${1//-/_}_$2"
    if declare -F "${fn}_$DISTRO" >/dev/null; then
        echo "${fn}_$DISTRO"
    elif declare -F "$fn" >/dev/null; then
        echo "$fn"
    fi
}

# The body of a module. Runs in the background subshell with 'set -e'.
function module_body {
    local name="$1" fn
    if [ -n "${M_PKGS[$name]:-}" ]; then
        # shellcheck disable=SC2086 # the list is split on purpose
        pkg_install ${M_PKGS[$name]}
    fi
    fn="$(_hook "$name" install)"
    if [ -n "$fn" ]; then
        "$fn"
    fi
}

# Return 0 if a dependency of the module did not get installed
function _blocked {
    local dep
    for dep in ${M_DEPS[$1]:-}; do
        [ "${RESULT[$dep]:-}" == "ok" ] || return 0
    done
    return 1
}

# Ask what to do about a failed module: returns 10 retry, 11 skip or 12 abort. Without a
# terminal an optional module is skipped and a required one aborts the run.
function _on_failure {
    local name="$1" answer choices="[r]etry, [l]og, [s]kip, [a]bort"
    if has_flag "$name" required; then
        choices="[r]etry, [l]og, [a]bort"
    fi
    while [ -n "$INTERACTIVE" ]; do
        printf '[%s?%s] %s failed: %s? ' "$RED" "$NONE" "$name" "$choices" >/dev/tty
        read -r answer </dev/tty || break
        case "$answer" in
        r | R) return 10 ;;
        l | L) show_log ;;
        s | S) has_flag "$name" required || return 11 ;;
        a | A) return 12 ;;
        esac
    done
    if has_flag "$name" required; then
        return 12
    fi
    return 11
}

function run_module {
    local name="$1" index="$2" total="$3" label start action rc auto_retry=""
    # Modules are safe to run again and most failures are network problems. Without a
    # terminal nobody can press retry, so try once more.
    if [ -z "$INTERACTIVE" ]; then
        auto_retry=1
    fi
    label="$(printf '[%*d/%d] %s' "${#total}" "$index" "$total" "$name")"
    if _blocked "$name"; then
        RESULT["$name"]=blocked
        warn "$label: left out, a dependency failed."
        return 0
    fi
    printf '\n=== %s ===\n' "$label" >>"$LOG_FILE"
    while true; do
        start=$SECONDS
        if [ ! -t 1 ] || [ -n "$VERBOSE" ]; then
            info "$label"
        fi
        watched "$label" module_body "$name"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            RESULT["$name"]=ok
            info "$label done in $(_clock "$((SECONDS - start))")"
            return 0
        fi
        # The output of the module may not end with a newline
        printf '\n' >>"$LOG_FILE"
        error "$label failed after $(_clock "$((SECONDS - start))")."
        show_log_tail
        if [ -n "$auto_retry" ]; then
            auto_retry=""
            warn "$label: trying once more."
            continue
        fi
        action=0
        _on_failure "$name" || action=$?
        case "$action" in
        10) ;;
        11)
            RESULT["$name"]=failed
            return 0
            ;;
        *)
            RESULT["$name"]=failed
            return 1
            ;;
        esac
    done
}

# Wipe system wide package caches. Only with --minimal: they may be useful on a real machine.
function clean_system {
    if [ "$DISTRO" == "debian" ]; then
        run root apt-get clean
        run root find /var/lib/apt/lists -type f -delete
    else
        run root find /var/cache/pacman/pkg -mindepth 1 -delete
        run root find /var/lib/pacman/sync -type f -delete
    fi
}

function print_summary {
    local name failed=0 line
    printf '\n'
    for name in "${ORDER[@]}"; do
        case "${RESULT[$name]:-not run}" in
        ok) ;;
        *)
            failed=$((failed + 1))
            warn "$name: ${RESULT[$name]:-not run}"
            ;;
        esac
    done
    while IFS= read -r line; do
        info "$line"
    done <"$NOTES_FILE"
    if [ "$failed" -gt 0 ]; then
        error "$failed of ${#ORDER[@]} modules were not installed. Log: $LOG_FILE"
        return 1
    fi
    info "All ${#ORDER[@]} modules installed in $(_clock "$SECONDS"). Log: $LOG_FILE"
}

function execute {
    local name i=0 hook rc=0
    for name in "${ORDER[@]}"; do
        hook="$(_hook "$name" prepare)"
        if [ -n "$hook" ]; then
            "$hook"
        fi
    done
    info "Running unattended from here on. Log: $LOG_FILE"
    for name in "${ORDER[@]}"; do
        i=$((i + 1))
        run_module "$name" "$i" "${#ORDER[@]}"
        rc=$?
        [ "$rc" -eq 0 ] || break
    done
    if [ -n "$MINIMAL" ]; then
        watched "Cleaning package caches" clean_system
        rc=$?
        [ "$rc" -eq 0 ] || warn "Cleaning the package caches failed."
    fi
    print_summary
}

function main {
    local rc
    parse_args "$@"
    detect_distro
    export PATH="$PATH:$HOME/.local/bin:$HOME/.cargo/bin"
    USER="$(id -un)"
    export USER

    load_modules
    validate_names

    if [ -n "$LIST" ]; then
        print_list
        return 0
    fi
    if [ -n "$SHOW_LOG" ]; then
        { : </dev/tty; } 2>/dev/null && INTERACTIVE=1
        show_last_log
        return 0
    fi
    if [ -n "$DRY_RUN" ]; then
        resolve_plan
        print_plan
        return 0
    fi

    if [ -z "$NO_CONFIRM" ] && { : </dev/tty; } 2>/dev/null; then
        INTERACTIVE=1
    fi

    init_run
    info "Logging into $LOG_FILE"
    check_root
    if [ -n "$INTERACTIVE" ]; then
        # The questions show the packaged versions
        watched "Refreshing package lists" pkg_sync
        rc=$?
        [ "$rc" -eq 0 ] || die "Refreshing the package lists failed. Log: $LOG_FILE"
    fi
    resolve_plan
    execute
}

main "$@"
