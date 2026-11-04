#!/bin/bash
# C++ toolchain and Conan.

module cxx --desc "C++ environment" --after "neovim" \
    --packages "clang gcc make cmake lldb" --packages-debian "g++ libc6-dev clang-format"
module conan --desc "Conan" --deps "cxx"

function cxx_install {
    nvim_mason clangd
}

function conan_install {
    if ! pipx list --short 2>/dev/null | grep -q '^conan '; then
        run pipx install conan
    fi
}
