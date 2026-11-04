#!/bin/bash
# FiraCode Nerd Font.

module fonts --no-minimal --desc "FiraCode Nerd Font" --packages "fontconfig unzip"

function fonts_install {
    if fc-list | grep -qi 'FiraCode Nerd'; then
        return 0
    fi
    download https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip "$TMPDIR/FiraCode.zip"
    mkdir -p "$HOME/.local/share/fonts/FiraCode"
    run unzip -o "$TMPDIR/FiraCode.zip" -x README.md LICENSE -d "$HOME/.local/share/fonts/FiraCode"
    run fc-cache -f
}
