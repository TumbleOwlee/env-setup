#!/usr/bin/env bash

# Lay out all connected outputs left to right at their preferred mode.
# MONITOR_PRIMARY (from local.conf) selects the primary output.
local_conf="${XDG_CONFIG_HOME:-$HOME/.config}/env-setup/local.conf"
if [ -f "$local_conf" ]; then
    # shellcheck source=/dev/null
    . "$local_conf"
fi

xrandr_out="$(xrandr)"
mapfile -t outputs < <(awk '$2 == "connected" {print $1}' <<<"$xrandr_out")
mapfile -t disconnected < <(awk '$2 == "disconnected" {print $1}' <<<"$xrandr_out")

[ "${#outputs[@]}" -gt 0 ] || exit 0

primary="${MONITOR_PRIMARY:-${outputs[0]}}"

args=()
x=0
for out in "${outputs[@]}"; do
    # first mode line after the output; prefer the one flagged '+' (preferred)
    mode=$(awk -v o="$out" '
        $1 == o {f = 1; next}
        f && /^[^ ]/ {exit}
        f && !first {first = $1}
        f && /\+/ && !pref {pref = $1}
        END {print (pref ? pref : first)}' <<<"$xrandr_out")
    args+=(--output "$out" --mode "$mode" --pos "${x}x0" --rotate normal)
    [ "$out" = "$primary" ] && args+=(--primary)
    x=$((x + ${mode%%x*}))
done

for out in "${disconnected[@]}"; do
    args+=(--output "$out" --off)
done

echo "xrandr ${args[*]}"
xrandr "${args[@]}"
