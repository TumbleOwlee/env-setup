#!/bin/bash
# Alacritty and its configuration. Packaged on Arch, built from source on Debian/Ubuntu.

module alacritty --no-minimal --desc "alacritty" --packages-arch "alacritty" --deps-debian "rustup" \
    --packages-debian "cmake g++ pkg-config libfreetype6-dev libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev"

function _alacritty_config {
    local dir="$HOME/.config/alacritty"
    mkdir -p "$dir"
    if [ -f "$dir/alacritty.yml" ]; then
        mv "$dir/alacritty.yml" "$dir/alacritty.yml.bak.$(date +%Y%m%d%H%M%S)"
    fi
    put "Configs/alacritty/alacritty.toml" "$dir/alacritty.toml" 644 backup
    note "If alacritty doesn't render the font, try: alacritty -o 'debug.renderer=\"gles2\"'"
}

function alacritty_install_arch {
    _alacritty_config
}

function alacritty_install_debian {
    local src="$TMPDIR/alacritty"
    if ! command -v alacritty >/dev/null 2>&1; then
        run git clone --depth=1 https://github.com/alacritty/alacritty.git "$src"
        (
            cd "$src" || exit 1
            cargo_cached build --release
        )
        run root install -m 755 "$src/target/release/alacritty" /usr/local/bin/alacritty
        if ! infocmp alacritty >/dev/null 2>&1; then
            run root tic -xe alacritty,alacritty-direct "$src/extra/alacritty.info"
        fi
    fi
    _alacritty_config
}
