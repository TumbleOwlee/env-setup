#!/bin/env bash

ps5controller="7C:66:EF:50:AE:10"
headphones="F8:4E:17:E8:B9:DF"

bluetoothctl devices Connected | grep "${ps5controller}" > /dev/null
if [ $? -eq 0 ]; then
    ps5controller_option="Disconnect PS5 Controller"
    ps5controller_cmd="bluetoothctl disconnect $ps5controller"
else
    bluetoothctl devices Paired | grep "${ps5controller}" > /dev/null
    if [ $? -eq 0 ]; then
        ps5controller_option="Connect PS5 Controller"
        ps5controller_cmd="bluetoothctl connect $ps5controller"
    else
        ps5controller_option="Pair PS5 Controller"
        ps5controller_cmd="bluetoothctl pair $ps5controller"
    fi
fi

bluetoothctl devices Connected | grep "${headphones}" > /dev/null
if [ $? -eq 0 ]; then
    headphones_option="Disconnect Headphones"
    headphones_cmd="bluetoothctl disconnect $headphones"
else
    bluetoothctl devices Paired | grep "${headphones}" > /dev/null
    if [ $? -eq 0 ]; then
        headphones_option="Connect Headphones"
        headphones_cmd="bluetoothctl connect $headphones"
    else
        headphones_option="Pair Headphones"
        headphones_cmd="bluetoothctl pair $headphones"
    fi
fi

activatescan_option="Activate Scan"
activatescan_cmd="bluetoothctl scan on"

# Get answer from user via rofi
selected_option=$(echo "$ps5controller_option
$headphones_option
$activatescan_option" | rofi -dmenu\
                  -i\
                  -p "Bluetooth"\
                  -config "~/.config/rofi/bluetoothmenu.rasi"\
                  -font "Nerd Font 12"\
                  -width "15"\
                  -lines 1\
                  -line-margin 3\
                  -line-padding 10\
                  -scrollbar-width "0" )

# Do something based on selected option
if [ "$selected_option" == "$headphones_option" ]; then
    $headphones_cmd
elif [ "$selected_option" == "$ps5controller_option" ]; then
    $ps5controller_cmd
elif [ "$selected_option" == "$activatescan_option" ]; then
    $activatescan_cmd
else
    echo "No match"
fi
