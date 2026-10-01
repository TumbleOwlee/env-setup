#!/usr/bin/env bash

awk '/^[a-z]/ && last {print "<small>",$0,"\t",last,"</small>"} {last=""} /^#/{last=$0}' "$HOME/.config/sxhkd/sxhkdrc" |
    column -t -s $'\t' |
    rofi -dmenu -i -p "keybindings:" -markup-rows -no-show-icons \
        -theme-str 'window { width: 1000px; location: north; y-offset: 40px; } listview { lines: 15; scrollbar: false; }'
