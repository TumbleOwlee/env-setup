#!/bin/bash
# Build the development image of the Dockerfile with settings chosen on the terminal:
# Debian version, user, image tag and the modules to install. Needs docker with BuildKit.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=Unix/lib/menu.sh
source "$ROOT/Unix/lib/menu.sh"

if [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\e[1m' DIM=$'\e[2m' GREEN=$'\e[32m' CYAN=$'\e[36m' NONE=$'\e[0m'
else
    BOLD='' DIM='' GREEN='' CYAN='' NONE=''
fi

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
    trap menu_restore EXIT

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
