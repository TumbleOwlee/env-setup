#!/bin/bash
# shellcheck disable=SC2034 # color codes and CHILD are used by the sourcing scripts
# Terminal output, prompts, the log file and the background runner with its
# status line. Requires LOG_FILE, STATE_FILE, VERBOSE and INTERACTIVE from main.sh.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    NONE=$'\e[0m' RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' CYAN=$'\e[36m' BOLD=$'\e[1m' DIM=$'\e[2m'
else
    NONE='' RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM=''
fi

# Seconds between status lines if stdout is no terminal (a terminal gets one per second)
HEARTBEAT=10
CHILD=

function _print {
    printf '%s\n' "$1"
    printf '%s\n' "$2" >>"$LOG_FILE"
}

function info {
    _print "[${CYAN}+${NONE}] $*" "[+] $*"
}

function warn {
    _print "[${YELLOW}!${NONE}] $*" "[!] $*"
}

function error {
    _print "[${RED}!${NONE}] $*" "[!] $*" >&2
}

function die {
    printf '[%s!%s] %s\n' "$RED" "$NONE" "$*" >&2
    exit 1
}

# Ask a yes/no question: confirm <question> <Y|N>. Without a terminal the default applies.
function confirm {
    local answer=""
    if [ -n "$INTERACTIVE" ]; then
        printf '[%s?%s] %s ' "$YELLOW" "$NONE" "$1" >/dev/tty
        read -r answer </dev/tty || answer=""
    fi
    answer="${answer:-$2}"
    printf '[?] %s %s\n' "$1" "$answer" >>"$LOG_FILE"
    case "$answer" in
    y | Y | yes | YES) return 0 ;;
    *) return 1 ;;
    esac
}

# Format seconds. They are based on the system clock, which can step backwards.
function _clock {
    local secs=$(($1 < 0 ? 0 : $1))
    printf '%02d:%02d' "$((secs / 60))" "$((secs % 60))"
}

# Print the last log line without colors and carriage return updates
function _last_log_line {
    local line
    line="$(tail -n 1 "$LOG_FILE" 2>/dev/null | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g')"
    line="${line%$'\r'}"
    line="${line##*$'\r'}"
    printf '%s' "${line//[[:cntrl:]]/ }"
}

# Rewrite the single status line of the terminal, cut to its width
function _draw_status {
    local cols line
    cols="$(stty size </dev/tty 2>/dev/null)"
    cols="${cols##* }"
    line="$1"
    printf '\r\e[K%.*s' "$((${cols:-80} - 1))" "$line"
}

# Update the status once per second until the process <pid> ends: _watch <pid> <label>
function _watch {
    local pid="$1" label="$2" start=$SECONDS last=-1 elapsed text
    local live=""
    if [ -t 1 ] && [ -z "$VERBOSE" ]; then
        live=1
    fi
    while kill -0 "$pid" 2>/dev/null; do
        elapsed=$((SECONDS - start))
        if [ "$elapsed" -ne "$last" ]; then
            last=$elapsed
            text="$(<"$STATE_FILE")"
            if [ -n "$live" ]; then
                _draw_status "$label $(_clock "$elapsed") ${text:+| ${text:0:40} }| $(_last_log_line)"
            elif [ "$elapsed" -gt 0 ] && [ $((elapsed % HEARTBEAT)) -eq 0 ]; then
                printf '    %s still running %s%s\n' "$label" "$(_clock "$elapsed")" "${text:+: $text}"
            fi
        fi
        sleep 0.2
    done
    if [ -n "$live" ]; then
        printf '\r\e[K'
    fi
}

# Run a function in the background with all output in the log. It gets its own
# process group, so that an interrupt can stop everything it started.
function _spawn {
    : >"$STATE_FILE"
    set -m
    (
        set -eo pipefail
        "$@"
    ) >>"$LOG_FILE" 2>&1 </dev/null &
    CHILD=$!
    set +m
}

# Run a function with status line and return its exit code: watched <label> <function> [args]
# Never call this from a condition ('if', '||', '&&'), also not indirectly: bash then
# ignores 'set -e' in the function, even in the background subshell.
function watched {
    local label="$1" rc=0
    shift
    _spawn "$@"
    _watch "$CHILD" "$label"
    wait "$CHILD" || rc=$?
    CHILD=
    return "$rc"
}

function stop_child {
    if [ -n "$CHILD" ]; then
        kill -TERM -- "-$CHILD" 2>/dev/null
        CHILD=
    fi
}

# Show the whole log: in a pager if possible
function show_log {
    if [ -n "$INTERACTIVE" ] && command -v less >/dev/null 2>&1; then
        less -R "$LOG_FILE" </dev/tty >/dev/tty
    else
        cat "$LOG_FILE"
    fi
}

function show_log_tail {
    printf -- '--- last lines of %s ---\n' "$LOG_FILE"
    tail -n 40 "$LOG_FILE"
    printf -- '--- end of log ---\n'
}
