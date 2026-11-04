#!/bin/bash
# Build the development image of the Dockerfile with settings chosen on the terminal:
# Debian version, user, image tag and the modules to install. Needs docker with BuildKit.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\e[1m' DIM=$'\e[2m' GREEN=$'\e[32m' CYAN=$'\e[36m' NONE=$'\e[0m'
else
    BOLD='' DIM='' GREEN='' CYAN='' NONE=''
fi

# Filled by list_modules and read by _menu
LABELS=() CHECKED=() CURSOR=0 KEY=""

function die {
    printf '[!] %s\n' "$*" >&2
    exit 1
}

# Print "name<TAB>desc<TAB>1|0" for every module that can be chosen for the image,
# 1 if it is in the default image. The module files only define functions apart
# from 'module', so they are sourced with a 'module' that records the options.
# shellcheck disable=SC2317 # module is called by the sourced files
function list_modules {
    (
        function module {
            local name="$1" desc="" distros="" flags=" "
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                --desc) desc="$2" && shift 2 ;;
                --distros) distros="$2" && shift 2 ;;
                --packages | --packages-* | --deps | --deps-* | --after) shift 2 ;;
                *) flags+="${1#--} " && shift ;;
                esac
            done
            # The image is Debian, base is always installed
            if [[ -n "$distros" && " $distros " != *" debian "* ]] ||
                [[ "$flags" == *" internal "* || "$flags" == *" required "* ]]; then
                return 0
            fi
            local on=1
            if [[ "$flags" == *" no-minimal "* || "$flags" == *" optional "* ]]; then
                on=0
            fi
            printf '%s\t%s\t%s\n' "$name" "$desc" "$on"
        }
        for f in "$ROOT"/Unix/modules/*.sh; do
            # shellcheck disable=SC1090
            source "$f"
        done
    )
}

# ---------------------------------------------------------------------------
# Prompts. Everything is drawn on /dev/tty, inline below the question.
# ---------------------------------------------------------------------------

# Read one key press into KEY: up, down, space, enter, all, quit or other
function read_key {
    local k rest=""
    IFS= read -rsn1 k </dev/tty
    if [ "$k" == $'\e' ]; then
        IFS= read -rsn2 -t 0.05 rest </dev/tty || true
        k+="$rest"
    fi
    case "$k" in
    $'\e[A' | k) KEY=up ;;
    $'\e[B' | j) KEY=down ;;
    ' ') KEY=space ;;
    '') KEY=enter ;;
    a) KEY=all ;;
    q | $'\e') KEY=quit ;;
    *) KEY=other ;;
    esac
}

# Replace the question line by the question with its answer
function _answered {
    printf '%s?%s %s %s%s%s\n' "$GREEN" "$NONE" "$1" "$CYAN" "$2" "$NONE" >/dev/tty
}

# A list of LABELS below <question>, moved through with the arrow keys or j/k.
# multi: space toggles CHECKED, a toggles all. Sets CURSOR. The list is removed
# afterwards: _menu <single|multi> <question> <hint>
function _menu {
    local mode="$1" question="$2" hint="$3" n=${#LABELS[@]} i mark first=1
    CURSOR=0
    printf '\e[?25l%s?%s %s %s%s%s\n' "$GREEN" "$NONE" "$question" "$DIM" "$hint" "$NONE" >/dev/tty
    while true; do
        if [ -z "$first" ]; then
            printf '\e[%dA' "$n" >/dev/tty
        fi
        first=""
        for ((i = 0; i < n; i++)); do
            mark=""
            if [ "$mode" == multi ]; then
                mark="[ ] "
                if [ "${CHECKED[i]}" == 1 ]; then
                    mark="[${GREEN}x${NONE}] "
                fi
            fi
            if [ "$i" -eq "$CURSOR" ]; then
                printf '\r\e[K%s>%s %s%s%s%s\n' "$CYAN" "$NONE" "$mark" "$BOLD" "${LABELS[i]}" "$NONE"
            else
                printf '\r\e[K  %s%s\n' "$mark" "${LABELS[i]}"
            fi
        done >/dev/tty
        read_key
        case "$KEY" in
        up) CURSOR=$(((CURSOR + n - 1) % n)) ;;
        down) CURSOR=$(((CURSOR + 1) % n)) ;;
        space)
            if [ "$mode" == multi ]; then
                CHECKED[CURSOR]=$((1 - CHECKED[CURSOR]))
            fi
            ;;
        all)
            if [ "$mode" == multi ]; then
                local v=1
                if [[ " ${CHECKED[*]} " != *" 0 "* ]]; then
                    v=0
                fi
                for ((i = 0; i < n; i++)); do
                    CHECKED[i]=$v
                done
            fi
            ;;
        enter) break ;;
        quit) exit 1 ;;
        esac
    done
    printf '\e[%dA\r\e[J\e[?25h' "$((n + 1))" >/dev/tty
}

# Read a line with an editable default: ask_text <question> <default>, sets REPLY
function ask_text {
    read -e -r -i "$2" -p "${GREEN}?${NONE} $1 " REPLY
}

# Ask yes/no, default yes: confirm <question>
function confirm {
    local answer
    read -r -p "${GREEN}?${NONE} $1 ${DIM}[Y/n]${NONE} " answer
    [[ "$answer" =~ ^([yY]|[yY]es|)$ ]]
}

function main {
    local version user tag shown flags list name desc on i
    local names=() selected=() versions=(stable 13 12 testing)

    command -v docker >/dev/null 2>&1 || die "docker is not installed."
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        die "This script needs a terminal."
    fi
    trap 'printf "\e[?25h" >/dev/tty; stty echo </dev/tty 2>/dev/null || true' EXIT

    LABELS=("stable   current stable release" "13       trixie" "12       bookworm" "testing  next release")
    _menu single "Debian version" "(up/down, enter)"
    version="${versions[CURSOR]}"
    _answered "Debian version" "$version"

    ask_text "User name:" dev
    user="$REPLY"
    [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid user name '$user'."
    ask_text "Image tag:" dev-env
    tag="$REPLY"
    [ -n "$tag" ] || die "The image tag is empty."

    LABELS=() CHECKED=()
    while IFS=$'\t' read -r name desc on; do
        names+=("$name")
        LABELS+=("$(printf '%-11s %s%s%s' "$name" "$DIM" "$desc" "$NONE")")
        CHECKED+=("$on")
    done < <(list_modules)
    _menu multi "Modules" "(space toggles, a all, enter; base and dependencies are added)"
    for ((i = 0; i < ${#names[@]}; i++)); do
        if [ "${CHECKED[i]}" == 1 ]; then
            selected+=("${names[i]}")
        fi
    done
    _answered "Modules" "${selected[*]:-base only}"

    # --only limits the run to the selection, --include lifts the --minimal limit for it
    flags="--only=base"
    if [ ${#selected[@]} -gt 0 ]; then
        list="$(
            IFS=,
            echo "${selected[*]}"
        )"
        flags="--only=$list --include=$list"
    fi

    local cmd=(docker build
        --build-arg "DEBIAN_VERSION=$version"
        --build-arg "DEV_USER=$user"
        --build-arg "SETUP_FLAGS=$flags"
        -t "$tag" "$ROOT")
    shown=""
    for i in "${cmd[@]}"; do
        if [[ "$i" == *" "* ]]; then
            i="\"$i\""
        fi
        shown+=" $i"
    done
    printf '\n %s\n\n' "$shown"
    confirm "Build the image?" || exit 1

    DOCKER_BUILDKIT=1 "${cmd[@]}"
    printf '\nRun it with:\n  docker run --rm -it -v "%s":/work -w /work %s\n' "\$PWD" "$tag"
}

main "$@"
