#!/bin/bash
# rustup with the stable toolchain, the rust environment and cross.

module rustup --internal --desc "rustup and the stable toolchain"
module rust --desc "rust environment" --deps "rustup" --after "neovim"
module rust-cross --no-minimal --desc "cross and libclang" --deps "rust" --packages "libclang"

function rustup_prepare {
    if ! command -v rustup >/dev/null 2>&1; then
        choose_upstream rustup rustup
    fi
}

function rustup_install {
    local profile=default
    if [ -n "$MINIMAL" ]; then
        # The default profile contains about 900 MB of docs
        profile=minimal
    fi
    if ! command -v rustup >/dev/null 2>&1; then
        if use_upstream rustup; then
            run_installer https://sh.rustup.rs -y --no-modify-path --default-toolchain none
        else
            pkg_install rustup
        fi
    fi
    run rustup toolchain install stable --profile "$profile"
    run rustup default stable
}

function rust_install {
    run rustup component add rustfmt clippy rust-src rust-analyzer
    nvim_mason rust-analyzer
}

function rust_cross_install {
    if ! command -v cross >/dev/null 2>&1; then
        cargo_install cross --git https://github.com/cross-rs/cross
    fi
}
