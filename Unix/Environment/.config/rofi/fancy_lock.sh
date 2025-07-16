#!/bin/bash

i3lock \
    --blur 5 \
    --bar-indicator \
    --bar-pos y+h \
    --bar-direction 1 \
    --bar-max-height 5 \
    --bar-base-width 5 \
    --bar-color 000000cc \
    --keyhl-color 8f7c56cc \
    --bar-periodic-step 50 \
    --bar-step 50 \
    --wrong-text "" \
    --verif-text "" \
    --redraw-thread \
    --clock \
    --force-clock \
    --time-pos x+5:y+h-80 \
    --time-color 8f7c56ff \
    --date-pos tx:ty+15 \
    --date-color 8f7c56ff \
    --date-align 1 \
    --time-align 1 \
    --ringver-color 8f7c5688 \
    --ringwrong-color ff000088 \
    --status-pos x+5:y+h-16 \
    --verif-align 1 \
    --wrong-align 1 \
    --verif-color ffffffff \
    --wrong-color ffffffff \
    --modif-pos -50:-50

