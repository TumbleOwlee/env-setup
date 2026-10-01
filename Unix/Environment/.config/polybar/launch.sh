#!/usr/bin/env bash

# Optional overrides: MONITOR_PRIMARY, WLAN_IF, BATTERY, ADAPTER, BACKLIGHT
local_conf="${XDG_CONFIG_HOME:-$HOME/.config}/env-setup/local.conf"
if [ -f "$local_conf" ]; then
    # shellcheck source=/dev/null
    . "$local_conf"
fi

detect_wlan() {
    local d
    for d in /sys/class/net/*/wireless; do
        if [ -d "$d" ]; then
            basename "$(dirname "$d")"
            return 0
        fi
    done
    return 1
}

detect_supply() {
    local want="$1" d
    for d in /sys/class/power_supply/*; do
        if [ -r "$d/type" ] && [ "$(cat "$d/type")" = "$want" ]; then
            basename "$d"
            return 0
        fi
    done
    return 1
}

detect_backlight() {
    local d
    for d in /sys/class/backlight/*; do
        if [ -e "$d" ]; then
            basename "$d"
            return 0
        fi
    done
    return 1
}

# Detected values only apply when local.conf did not set them
WLAN_IF="${WLAN_IF:-$(detect_wlan)}"
BATTERY="${BATTERY:-$(detect_supply Battery)}"
ADAPTER="${ADAPTER:-$(detect_supply Mains)}"
BACKLIGHT="${BACKLIGHT:-$(detect_backlight)}"
# Only export what we have, so the config.ini defaults apply otherwise
[ -n "$WLAN_IF" ] && export WLAN_IF
[ -n "$BATTERY" ] && export BATTERY
[ -n "$ADAPTER" ] && export ADAPTER
[ -n "$BACKLIGHT" ] && export BACKLIGHT

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 1; done

mapfile -t monitors < <(polybar --list-monitors | cut -d: -f1)
primary="${MONITOR_PRIMARY:-$(polybar --list-monitors | awk -F: '/\(primary\)/ {print $1; exit}')}"
primary="${primary:-${monitors[0]}}"

# The "top" bar carries the tray (only one bar may own it); others use "second"
for m in "${monitors[@]}"; do
    bar=second
    [ "$m" = "$primary" ] && bar=top
    MONITOR="$m" polybar "$bar" -c "$HOME/.config/polybar/config.ini" &
done
