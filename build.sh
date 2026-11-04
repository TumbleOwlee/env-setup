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

# Filled by main and read by _menu
LABELS=() HINTS=() CHECKED=() CURSOR=0 KEY=""

function die {
    printf '[!] %s\n' "$*" >&2
    exit 1
}

# Print "name<TAB>desc<TAB>1|0" for every module that can be chosen for the image,
# 1 if it is in the default image. The module files only define functions apart
# from 'module', so they are sourced with a 'module' that records the options.
# shellcheck disable=SC2317,SC2329 # module is called by the sourced files
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

# Print the terminal size as "rows cols", 24x80 if unknown
function _term_size {
    local size
    size="$(stty size </dev/tty 2>/dev/null)" || size=""
    if [[ "$size" =~ ^[0-9]+\ [0-9]+$ ]]; then
        echo "$size"
    else
        echo "24 80"
    fi
}

# A list of LABELS (with dim HINTS) below <question>, moved through with the arrow keys
# or j/k. multi: space toggles CHECKED, a toggles all. Sets CURSOR. Only as many entries
# as fit into the terminal are shown and every line is cut to its width, so that the
# list can be redrawn in place. It is removed afterwards: _menu <single|multi> <question> <hint>
function _menu {
    local mode="$1" question="$2" hint="$3" n=${#LABELS[@]} i mark rows cols
    local top=0 height drawn=0 avail label more
    CURSOR=0
    read -r rows cols <<<"$(_term_size)"
    question="? $question"
    hint="${hint:0:$((cols - 2 - ${#question} > 0 ? cols - 2 - ${#question} : 0))}"
    printf '\e[?25l%s?%s%s %s%s%s\n' "$GREEN" "$NONE" "${question:1:$((cols - 2))}" "$DIM" "$hint" "$NONE" >/dev/tty
    while true; do
        read -r rows cols <<<"$(_term_size)"
        # Keep the question, the 'more' line and one spare line visible
        height=$((rows - 3 < n ? rows - 3 : n))
        if [ "$height" -lt 1 ]; then
            height=1
        fi
        if [ "$CURSOR" -lt "$top" ]; then
            top=$CURSOR
        elif [ "$CURSOR" -ge $((top + height)) ]; then
            top=$((CURSOR - height + 1))
        fi
        if [ "$top" -gt $((n - height)) ]; then
            top=$((n - height))
        fi
        if [ "$drawn" -gt 0 ]; then
            printf '\e[%dA' "$drawn" >/dev/tty
        fi
        drawn=0
        {
            for ((i = top; i < top + height; i++)); do
                mark=""
                avail=$((cols - 3))
                if [ "$mode" == multi ]; then
                    mark="[ ] "
                    if [ "${CHECKED[i]}" == 1 ]; then
                        mark="[${GREEN}x${NONE}] "
                    fi
                    avail=$((avail - 4))
                fi
                label="${LABELS[i]:0:$((avail > 0 ? avail : 0))}"
                avail=$((avail - ${#label} - 1))
                hint=""
                if [ "$avail" -gt 0 ]; then
                    hint="${HINTS[i]:-}"
                    hint="${hint:0:avail}"
                fi
                if [ "$i" -eq "$CURSOR" ]; then
                    printf '\r\e[K%s>%s %s%s%s%s %s%s%s\n' "$CYAN" "$NONE" "$mark" "$BOLD" "$label" "$NONE" "$DIM" "$hint" "$NONE"
                else
                    printf '\r\e[K  %s%s %s%s%s\n' "$mark" "$label" "$DIM" "$hint" "$NONE"
                fi
                drawn=$((drawn + 1))
            done
            if [ "$height" -lt "$n" ]; then
                more="  ${top} more above, $((n - top - height)) more below"
                printf '\r\e[K%s%s%s\n' "$DIM" "${more:0:$((cols - 1))}" "$NONE"
                drawn=$((drawn + 1))
            fi
            # Lines left over from a taller terminal
            printf '\e[J'
        } >/dev/tty
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
    printf '\e[%dA\r\e[J\e[?25h' "$((drawn + 1))" >/dev/tty
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
    local version user uid gid tag shown flags list name desc on i
    local names=() selected=() versions=(stable 13 12 testing)

    command -v docker >/dev/null 2>&1 || die "docker is not installed."
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        die "This script needs a terminal."
    fi
    trap 'printf "\e[?25h" >/dev/tty; stty echo </dev/tty 2>/dev/null || true' EXIT

    LABELS=("stable  " "13      " "12      " "testing ")
    HINTS=("current stable release" "trixie" "bookworm" "next release")
    _menu single "Debian version" "(up/down, enter)"
    version="${versions[CURSOR]}"
    _answered "Debian version" "$version"

    ask_text "User name:" dev
    user="$REPLY"
    [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid user name '$user'."
    # Your own ids give the user access to the files you mount, root gets the default
    uid="$(id -u)" gid="$(id -g)"
    if [ "$uid" -eq 0 ]; then
        uid=1000 gid=1000
    fi
    ask_text "User id:" "$uid"
    uid="$REPLY"
    ask_text "Group id:" "$gid"
    gid="$REPLY"
    [[ "$uid" =~ ^[1-9][0-9]*$ && "$gid" =~ ^[1-9][0-9]*$ ]] || die "Invalid user or group id."
    ask_text "Image tag:" dev-env
    tag="$REPLY"
    [ -n "$tag" ] || die "The image tag is empty."

    LABELS=() HINTS=() CHECKED=()
    while IFS=$'\t' read -r name desc on; do
        names+=("$name")
        LABELS+=("$(printf '%-11s' "$name")")
        HINTS+=("$desc")
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
        --build-arg "DEV_UID=$uid"
        --build-arg "DEV_GID=$gid"
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
