#!/bin/bash

LOG_FILE="/tmp/setup_$(date +%Y_%m_%d_%H_%M_%S).log"

# Color codes
NONE="\e[0m";    BLACK="\e[30m"; RED="\e[31m";    GREEN="\e[32m"
YELLOW="\e[33m"; BLUE="\e[34m";  PURPLE="\e[35m"; CYAN="\e[36m"

trap "exit 1" SIGINT

# Print info
function info {
    echo -e "[${CYAN}+${NONE}] $@"
    echo -e "[+] $@" >>$LOG_FILE
}

# Print notify
function notify {
    echo -e "  [${GREEN}!${NONE}] $@"
    echo -e "  [!] $@" >>$LOG_FILE
}

# Ask for input
function ask {
    echo -e -n "[${YELLOW}?${NONE}] $1 " 1>&2
    echo -e -n "[?] $1 " >>$LOG_FILE
    read value
    if [ "_$value" == "_" ]; then
        echo "$2"
        echo "$2" >>$LOG_FILE
    else
        echo "$value"
        echo "$value" >>$LOG_FILE
    fi
}

# Ask for retry
function retry {
    echo -e -n "[${RED}?${NONE}] Retry? [Y/n] " 1>&2
    echo -e -n "[?] $1 " >>$LOG_FILE
    read value
    if [ "_$value" == "_n" ] || [ "_$value" == "_N" ]; then
        false
    else
        true
    fi
}

# Ask for termination
function terminate {
    echo -e -n "[${RED}?${NONE}] Terminate? [Y/n] " 1>&2
    echo -e -n "[?] $1 " >>$LOG_FILE
    read value
    if [ "_$value" == "_n" ] || [ "_$value" == "_N" ]; then
        false
    else
        exit 0
    fi
}

# Warn the user
function warn {
    echo -e "[${RED}!${NONE}] $1"
}

# Cache sudo privileges
info "Check for sudo privileges.."
sudo echo -n "" || exit

# Initialize log
touch $LOG_FILE
info "Logging into ${LOG_FILE}."

# Update and upgrade
info "Update and upgrade."
while true; do
    notify "Execute 'yay -Syyu'.."
    yay -Syyu --noconfirm >>$LOG_FILE 2>&1 && break || retry || terminate || break
done

# Install requirements
info "Install requirements."
while true; do
    notify "Execute 'yay -S'.."
    yay -S --noconfirm git curl python python-pipx >>$LOG_FILE 2>&1 && break || retry || terminate || break
done

# Install alacritty
resp=$(ask "Install alacritty? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install alacritty"
    while true; do
        notify "Execute 'yay -S'.."
        yay -S --noconfirm alacritty >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    # Create alacritty configuration
    while true; do
        notify "Create 'alacritty.yml'"
        mkdir -p ~/.config/alacritty >/dev/null 2>&1 && break || retry || terminate || break
        echo "window:" > ~/.config/alacritty/alacritty.yml 2>>$LOG_FILE && break || retry || terminate || break
        echo "  opacity: 0.9" >> ~/.config/alacritty/alacritty.yml 2>>$LOG_FILE && break || retry || terminate || break
        echo "font:" >> ~/.config/alacritty/alacritty.yml 2>>$LOG_FILE && break || retry || terminate || break
        echo "  size: 8.0" >> ~/.config/alacritty/alacritty.yml 2>>$LOG_FILE && break || retry || terminate || break
    done
fi

# Install fish
resp=$(ask "Install fish shell? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install fish shell"
    while true; do
        notify "Execute 'yay -S'.."
        yay -S --noconfirm fish >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    while true; do
        notify "Set 'fish' as default shell."
        sudo chsh -s $(which fish) >>$LOG_FILE 2>&1 && sudo usermod -s /usr/bin/fish $(whoami) >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    # Create fish configuration
    while true; do
        mkdir -p ~/.config/fish/functions >/dev/null 2>&1
        notify "Create 'fish_greeting.fish'"
        echo -e "function fish_greeting\nend" > ~/.config/fish/functions/fish_greeting.fish 2>>$LOG_FILE && break || retry || terminate || break
        notify "Create 'fish_prompt.fish'"
        echo -e "function fish_prompt --description 'Write out the prompt'\n    set -l laststatus \$status\n\n    set -l git_info\n    if set -l git_branch (command git symbolic-ref HEAD 2>/dev/null | string replace refs/heads/ '')\n        set git_branch (set_color -o blue)\"\$git_branch\"\n        set -l git_status\n        if not command git diff-index --quiet HEAD --\n            if set -l count (command git rev-list --count --left-right \$upstream...HEAD 2>/dev/null)\n                echo \$count | read -l ahead behind\n   if test \"\$ahead\" -gt 0\n                    set git_status \"\$git_status\"(set_color red)⬆\n                end\nif test \"\$behind\" -gt 0\n set git_status \"\$git_status\"(set_color red)⬇\n                end\n            end\n            for i in (git status --porcelain | string sub -l 2 | sort | uniq)\n                switch \$i\n                    case \".\"\n set git_status \"\$git_status\"(set_color green)'+'\n                    case \" D\"\n set git_status \"\$git_status\"(set_color red)'x'\n      case \"*M*\"\n                        set git_status \"\$git_status\"(set_color green)'*'\n                    case \"*R*\"\n                        set git_status \"\$git_status\"(set_color purple)'>'\n                    case \"*U*\"\n                        set git_status \"\$git_status\"(set_color brown)'='\n                    case \"??\"\n                        set git_status \"\$git_status\"(set_color red)'!='\n                end\n            end\n        else\n            set git_status (set_color green):\n        end\n        set git_info \"(git\$git_status\$git_branch\"(set_color white)\")\"\n    end\n\n    # Disable PWD shortening by default.\n    set -q fish_prompt_pwd_dir_length\n    or set -lx fish_prompt_pwd_dir_length 0\n\n    set_color -b black\n    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s' (set_color -o white) '(' (set_color brcyan) \$USER (set_color white) '|' (set_color yellow) (prompt_pwd) (set_color white) \$git_info (set_color white) ')' (set_color white)\n    if test \$laststatus -eq 0\n        printf \"%s[0]%s>%s \" (set_color -o green) (set_color white) (set_color normal)\n    else\n        printf \"%s[%s]%s>%s \" (set_color -o red) \$laststatus (set_color white) (set_color normal)\n    end\nend" > ~/.config/fish/functions/fish_prompt.fish 2>>$LOG_FILE && break || retry || terminate || break
    done
fi

# Install tmux
resp=$(ask "Install tmux? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install tmux"
    while true; do
        notify "Execute 'yay -S'.."
        yay -S --noconfirm tmux >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    # Create tmux configuration
    while true; do
        notify "Create '.tmux.conf'"
        echo "set -g status off" > ~/.tmux.conf && break || retry || terminate || break
    done
fi

# Install neovim
NEOVIM=1
resp=$(ask "Install neovim? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install neovim"
    while true; do
        notify "Execute 'yay -S'.."
        yay -S --noconfirm neovim >>$LOG_FILE 2>&1 && NEOVIM=0 && break || retry || terminate || break
    done

    # Get neovim configuration
    while true; do
        notify "Create 'init.lua' and install packer."
        mkdir -p ~/.config/nvim >/dev/null 2>&1
        git clone https://github.com/wbthomason/packer.nvim ~/.local/share/nvim/site/pack/packer/start/packer.nvim >>$LOG_FILE 2>&1 || (cd ~/.local/share/nvim/site/pack/packer/start/packer.nvim && git pull >>$LOG_FILE 2>&1) && break || retry || terminate || break
        curl https://raw.githubusercontent.com/TumbleOwlee/neovim-config/main/init.lua > ~/.config/nvim/init.lua 2>>$LOG_FILE && break || retry || terminate || break
    done

    # Install neovim plugins
    while true; do
        notify "Install neovim plugins.."
        nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerInstall' >$LOG_FILE 2>&1 && break || retry || terminate || break
    done
fi

# Install docker
resp=$(ask "Install docker? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install docker"
    while true; do
        notify "Execute 'yay -S'"
        yay -S --noconfirm docker docker-compose >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    while true; do
        notify "Add user to docker group."
        sudo groupadd docker >>$LOG_FILE 2>&1
        sudo usermod -aG docker $USER >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
fi

# Install rust environment
resp=$(ask "Install rust environment? [y/N]" "N")
if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
    info "Install rustup"
    resp=$(ask "Install bleeding edge? [Y/n]" "Y")
    if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
        pkg="rustup-git"
    else
        pkg="rustup"
    fi
    while true; do
        notify "Execute 'yay -S'.."
        yay -S --noconfirm $pkg >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    # Install toolchain
    while true; do
        notify "Install toolchain.."
        rustup toolchain install stable >$LOG_FILE 2>&1 && break || retry || terminate || break
        rustup default stable >$LOG_FILE 2>&1 && break || retry || terminate || break
        rustup component add rust-src rust-analyzer >$LOG_FILE 2>&1 && break || retry || terminate || break
    done

    if [ $NEOVIM ]; then
        while true; do
            notify "Install neovim rust-analyzer LSP support"
            nvim --headless -c "MasonInstall rust-analyzer" -c "quitall"  >$LOG_FILE 2>&1 && break || retry || terminate || break
        done
    fi
fi

# Install C++ environment
resp=$(ask "Install C++ environment? [y/N]" "N")
if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
    info "Install clang, gcc, cmake"
    while true; do
        notify "Execute 'yay -S'.."
        yay -S --noconfirm clang gcc cmake >>$LOG_FILE 2>&1 && break || retry || terminate || break
    done
    
    if [ $NEOVIM ]; then
        while true; do
            notify "Install neovim clangd LSP support"
            nvim --headless -c "MasonInstall clangd" -c "quitall"  >$LOG_FILE 2>&1 && break || retry || terminate || break
        done
    fi
    
    resp=$(ask "Install Conan? [y/N]" "N")
    if [ "_$resp" == "_y" ] || [ "_$resp" == "_Y" ]; then
        while true; do
            notify "Execute 'pipx install'.."
            pipx install conan >$LOG_FILE 2>&1 && break || retry || terminate || break
            warn "Make sure '~/.local/bin' is in \$PATH"
        done
    fi
fi
