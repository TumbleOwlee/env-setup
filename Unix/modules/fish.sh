#!/bin/bash
# Fish as login shell, its functions and the owned conf.d snippet.

module fish --desc "fish shell" --packages "fish"

function fish_install {
    local fish_path fn
    fish_path="$(command -v fish)"
    if ! grep -qxF "$fish_path" /etc/shells 2>/dev/null; then
        printf '%s\n' "$fish_path" | root tee -a /etc/shells >/dev/null
    fi
    if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$fish_path" ]; then
        run root chsh -s "$fish_path" "$USER"
    fi

    for fn in fish_greeting fish_prompt colored_cat; do
        put "Configs/fish/$fn.fish" "$HOME/.config/fish/functions/$fn.fish" 644
    done

    write_owned "$HOME/.config/fish/conf.d/env-setup.fish" <<'SNIPPET'
# Managed by env-setup, rewritten on every run. Do not edit.
if functions -q fish_add_path
    fish_add_path -g $HOME/.local/bin $HOME/.cargo/bin
else
    for dir in $HOME/.local/bin $HOME/.cargo/bin
        contains $dir $PATH; or set PATH $dir $PATH
    end
end
if command -q zoxide
    zoxide init --cmd cd fish | source
end
alias ccat='command cat'
alias cat=colored_cat
if command -q nvim
    abbr -a vim nvim
    abbr -a vi nvim
    abbr -a v nvim
end
SNIPPET
}
