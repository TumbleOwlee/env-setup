#!/bin/sh
yad --title="bspwm keybindings:" \
    --no-buttons --geometry=450x500-15-400 --list \
    --column=key: --column=description: --column=command: \
    "ESC" "close this app" "" \
    "Super" "modkey" "(Mod4)" \
    "+Return" "open a terminal" "(alacritty)" \
    "+w" "open browser" "(firefox)" \
    "+n" "open file browser" "(thunar)" \
    "+d" "app menu" "(rofi)" \
    "+Ctrl+d" "window switcher" "(rofi)" \
    "+Shift+d" "ssh sessions" "(rofi)" \
    "+q" "close focused app" "(bspc node -c)" \
    "+Shift+q" "kill focused app" "(bspc node -k)" \
    "Print" "screenshot" "(scrot)" \
    "+Print" "screenshot menu" "(rofi)" \
    "+Shift+e" "power menu" "(rofi)" \
    "+Ctrl+Shift+q" "lock screen" "(i3lock)" \
    "+Shift+b" "bluetooth menu" "(rofi)" \
    "+F1" "open keybinding helper" "full list" \
    "+Shift+r" "restart bspwm" "bspc wm -r" \
    "+ESC" "reload sxhkd" "pkill -USR1 -x sxhkd"
