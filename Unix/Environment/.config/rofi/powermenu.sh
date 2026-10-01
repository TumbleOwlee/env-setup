#!/usr/bin/env bash

# Options for powermenu
logout="    Logout"
lock="    Lock"
shutdown="    Shutdown"
reboot="    Reboot"
sleep="    Sleep"

# Get answer from user via rofi (size comes from powermenu.rasi)
selected_option=$(echo "$lock
$logout
$sleep
$reboot
$shutdown" | rofi -dmenu -i -p "Power" \
    -config "$HOME/.config/rofi/powermenu.rasi" \
    -font "Nerd Font 12" \
    -theme-str 'listview { lines: 5; scrollbar: false; }')

# Do something based on selected option
if [ "$selected_option" == "$lock" ]; then
    "$HOME/.config/rofi/fancy_lock.sh"
elif [ "$selected_option" == "$logout" ]; then
    bspc quit
elif [ "$selected_option" == "$shutdown" ]; then
    systemctl poweroff
elif [ "$selected_option" == "$reboot" ]; then
    systemctl reboot
elif [ "$selected_option" == "$sleep" ]; then
    amixer set Master mute
    systemctl suspend
else
    echo "No match"
fi
