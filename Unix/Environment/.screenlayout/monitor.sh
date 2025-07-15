#!/bin/sh

setup() {
    connector="$1"
    position="$2"
    additional_args="$3"
    xrandr_args=""

    xrandr | grep "$connector connected" >/dev/null
    if [ $? -eq 0 ]; then
        resolution="$(xrandr | grep -A 1 "$connector connected" | grep -v $connector | awk '{print $1}')"
        xrandr_args="$xrandr_args --output $connector $additional_args --mode $resolution --pos $position --rotate normal "
    fi

    echo "$xrandr_args"
}

xrandr_cmd=""
xrandr_cmd="$xrandr_cmd$(setup 'DisplayPort-2' '0x0')"
xrandr_cmd="$xrandr_cmd$(setup 'DisplayPort-0' '0x1440' '--primary')"
xrandr_cmd="$xrandr_cmd --output HDMI-A-0 --off"

if [ "$xrandr_cmd" != "" ]; then
    echo "xrandr $xrandr_cmd"
    xrandr $xrandr_cmd
fi
