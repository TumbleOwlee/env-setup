#!/usr/bin/env bash

# BT_DEVICES is a bash array of 'Name|AA:BB:CC:DD:EE:FF' entries,
# defined in ~/.config/env-setup/local.conf
BT_DEVICES=()
# shellcheck source=/dev/null
[ -f "$HOME/.config/env-setup/local.conf" ] && . "$HOME/.config/env-setup/local.conf"

if [ "${#BT_DEVICES[@]}" -eq 0 ]; then
    echo "no devices configured" | rofi -dmenu -i -p "Bluetooth" \
        -config "$HOME/.config/rofi/bluetoothmenu.rasi" \
        -font "Nerd Font 12" \
        -theme-str 'listview { lines: 1; scrollbar: false; }' >/dev/null
    exit 0
fi

options=()
cmds=()
for entry in "${BT_DEVICES[@]}"; do
    name="${entry%%|*}"
    mac="${entry#*|}"
    if bluetoothctl devices Connected | grep -q "$mac"; then
        options+=("Disconnect $name")
        cmds+=("disconnect $mac")
    elif bluetoothctl devices Paired | grep -q "$mac"; then
        options+=("Connect $name")
        cmds+=("connect $mac")
    else
        options+=("Pair $name")
        cmds+=("pair $mac")
    fi
done
options+=("Activate Scan")
cmds+=("scan on")

# Get answer from user via rofi
selected_index=$(printf '%s\n' "${options[@]}" | rofi -dmenu -i -p "Bluetooth" -format i \
    -config "$HOME/.config/rofi/bluetoothmenu.rasi" \
    -font "Nerd Font 12" \
    -theme-str "listview { lines: ${#options[@]}; scrollbar: false; }")

if [ -n "$selected_index" ]; then
    # shellcheck disable=SC2086
    bluetoothctl ${cmds[$selected_index]}
else
    echo "No match"
fi
