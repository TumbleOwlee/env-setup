#!/bin/bash
# The interactive list used by build.sh and the setup, drawn on /dev/tty inline below
# the question. Requires GREEN, CYAN, BOLD, DIM and NONE from the sourcing script.

# Filled by the caller and read by _menu
LABELS=() HINTS=() CHECKED=() CURSOR=0 KEY="" MENU_OPEN=""

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
    MENU_OPEN=1
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
    MENU_OPEN=""
}

# Bring the terminal back if the script ends while a menu is open
function menu_restore {
    if [ -n "$MENU_OPEN" ]; then
        MENU_OPEN=""
        printf '\e[?25h' >/dev/tty
        stty echo </dev/tty 2>/dev/null || true
    fi
}
