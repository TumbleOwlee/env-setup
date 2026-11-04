#!/bin/bash
# Delta and the git configuration.

module delta --desc "delta"

function delta_prepare {
    if ! command -v delta >/dev/null 2>&1; then
        choose_upstream delta delta
    fi
}

# Install delta from the GitHub release
function _delta_upstream {
    local machine tag base triple deb_arch
    machine="$(uname -m)"
    tag="$(github_latest_tag dandavison/delta)"
    base="https://github.com/dandavison/delta/releases/download/$tag"
    if [ "$DISTRO" == "debian" ]; then
        case "$machine" in
        x86_64) deb_arch=amd64 ;;
        aarch64) deb_arch=arm64 ;;
        *) deb_arch="$machine" ;;
        esac
        download "$base/git-delta_${tag}_${deb_arch}.deb" "$TMPDIR/delta.deb"
        run root dpkg -i "$TMPDIR/delta.deb"
    else
        case "$machine" in
        x86_64) triple=x86_64-unknown-linux-musl ;;
        *) triple="$machine-unknown-linux-gnu" ;;
        esac
        download "$base/delta-$tag-$triple.tar.gz" "$TMPDIR/delta.tar.gz"
        run tar -xzf "$TMPDIR/delta.tar.gz" --strip-components=1 -C "$TMPDIR"
        mkdir -p "$HOME/.local/bin"
        install -m 755 "$TMPDIR/delta" "$HOME/.local/bin/delta"
    fi
}

function delta_install {
    local target="$HOME/.config/git/env-setup.gitconfig" regex
    if ! command -v delta >/dev/null 2>&1; then
        if use_upstream delta; then
            _delta_upstream
        else
            pkg_install delta
        fi
    fi
    download https://raw.githubusercontent.com/dandavison/delta/main/themes.gitconfig "$HOME/.config/delta/themes.gitconfig"
    put "Configs/git/gitconfig" "$target" 644
    regex="^$(printf '%s' "$target" | sed 's/[][\.*^$/]/\\&/g')\$"
    run git config --global --replace-all include.path "$target" "$regex"
}
