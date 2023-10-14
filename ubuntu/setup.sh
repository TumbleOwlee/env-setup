#!/bin/bash

LOG_FILE="/tmp/setup_$(date +%Y_%m_%d_%H_%M_%S).log"

# Color codes
NONE="\e[0m"
BLACK="\e[30m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
PURPLE="\e[35m"
CYAN="\e[36m"

trap "exit 1" SIGINT

# Print info
function info {
    echo -e "[${CYAN}+${NONE}] $@"
    echo -e "[+] $@" >>$LOG_FILE
}

# Print notify
function notify {
    echo -e "[${GREEN}!${NONE}] $@"
    echo -e "[!] $@" >>$LOG_FILE
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

# Initialize log
touch $LOG_FILE
info "Logging into ${LOG_FILE}."

# Update and upgrade
info "Update and upgrade."
notify "Execute 'apt update'.."
sudo apt update >>$LOG_FILE 2>&1 || exit
notify "Execute 'apt upgrade'.."
sudo apt upgrade -y >>$LOG_FILE 2>&1 || exit

# Install requirements
info "Install requirements."
notify "Execute 'apt install'.."
sudo apt install -y git curl python3 python3-pip >>$LOG_FILE 2>&1 || exit

# Install alacritty
resp=$(ask "Install alacritty? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install alacritty"
    notify "Add 'ppa:aslatter/ppa'.."
    sudo add-apt-repository ppa:aslatter/ppa -y >>$LOG_FILE 2>&1 || exit
    notify "Execute 'apt update'.."
    sudo apt update >>$LOG_FILE 2>&1 || exit
    notify "Execute 'apt install'.."
    sudo apt install -y alacritty >>$LOG_FILE 2>&1 || exit

    # Create alacritty configuration
    notify "Create 'alacritty.yml'"
    mkdir -p ~/.config/alacritty >/dev/null 2>&1 || exit
    echo "window:" > ~/.config/alacritty/alacritty.yml 2>>$LOG_FILE || exit
    echo "  opacity: 0.9" >> ~/.config/alacritty/alacritty.yml 2>>$LOG_FILE || exit
    echo "font:" >> ~/.config/alacritty/alacritty.yml 2>>$LOG_FILE || exit
    echo "  size: 8.0" >> ~/.config/alacritty/alacritty.yml 2>>$LOG_FILE || exit
fi

# Install fish
resp=$(ask "Install fish shell? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    notify "Execute 'apt install'.."
    sudo apt install -y fish >>$LOG_FILE 2>&1 || exit
    notify "Set 'fish' as default shell."
    sudo chsh -s $(which fish) >$LOG_FILE 2>&1 && sudo usermod -s /usr/bin/fish $(whoami) >$LOG_FILE 2>&1 || exit

    # Create fish configuration
    notify "Create 'fish_greeting.fish'"
    echo -e "function fish_greeting\nend" > ~/.config/fish/functions/fish_greeting.fish 2>>$LOG_FILE || exit
    notify "Create 'fish_prompt.fish'"
    echo -e "function fish_prompt --description 'Write out the prompt'\n    set -l laststatus \$status\n\n    set -l git_info\n    if set -l git_branch (command git symbolic-ref HEAD 2>/dev/null | string replace refs/heads/ '')\n        set git_branch (set_color -o blue)\"\$git_branch\"\n        set -l git_status\n        if not command git diff-index --quiet HEAD --\n            if set -l count (command git rev-list --count --left-right \$upstream...HEAD 2>/dev/null)\n                echo \$count | read -l ahead behind\n                if test \"\$ahead\" -gt 0\n                    set git_status \"\$git_status\"(set_color red)⬆\n                end\n                if test \"\$behind\" -gt 0\n
    set git_status \"\$git_status\"(set_color red)⬇\n                end\n            end\n            for i in (git status --porcelain | string sub -l 2 | sort | uniq)\n                switch \$i\n                    case \".\"\n
              set git_status \"\$git_status\"(set_color green)'+'\n                    case \" D\"\n
    set git_status \"\$git_status\"(set_color red)'x'\n                    case \"*M*\"\n                        set git_status \"\$git_status\"(set_color green)'*'\n                    case \"*R*\"\n                        set git_status \"\$git_status\"(set_color purple)'>'\n                    case \"*U*\"\n                        set git_status \"\$git_status\"(set_color brown)'='\n                    case \"??\"\n                        set git_status \"\$git_status\"(set_color red)'!='\n                end\n            end\n        else\n            set git_status (set_color green):\n        end\n        set git_info \"(git\$git_status\$git_branch\"(set_color white)\")\"\n    end\n\n    # Disable PWD shortening by default.\n    set -q fish_prompt_pwd_dir_length\n    or set -lx fish_prompt_pwd_dir_length 0\n\n    set_color -b black\n    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s' (set_color -o white) '(' (set_color brcyan) \$USER (set_color white) '|' (set_color yellow) (prompt_pwd) (set_color white) \$git_info (set_color white) ')' (set_color white)\n    if test \$laststatus -eq 0\n        printf \"%s[0]%s>%s \" (set_color -o green) (set_color white) (set_color normal)\n    else\n        printf \"%s[%s]%s>%s \" (set_color -o red) \$laststatus (set_color white) (set_color normal)\n    end\nend" > ~/.config/fish/functions/fish_prompt.fish 2>>$LOG_FILE || exit
fi

# Install tmux
resp=$(ask "Install tmux? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    notify "Execute 'apt install'.."
    sudo apt install -y tmux >>$LOG_FILE 2>&1 || exit

    # Create tmux configuration
    notify "Create '.tmux.conf'"
    echo "set -g status off" > ~/.tmux.conf
fi

# Install neovim
resp=$(ask "Install neovim? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install neovim"
    notify "Add 'neovim-ppa/unstable'."
    sudo add-apt-repository ppa:neovim-ppa/unstable -y >>$LOG_FILE 2>&1 || exit
    notify "Execute 'apt update'.."
    sudo apt update >>$LOG_FILE 2>&1 || exit
    notify "Execute 'apt install'.."
    sudo apt install -y neovim >>$LOG_FILE 2>&1 || exit

    # Get neovim configuration
    notify "Create 'init.lua' and install packer."
    mkdir -p ~/.config/nvim >/dev/null 2>&1
    git clone https://github.com/wbthomason/packer.nvim ~/.local/share/nvim/site/pack/packer/start/packer.nvim >>$LOG_FILE 2>&1 || (cd ~/.local/share/nvim/site/pack/packer/start/packer.nvim && git pull >$LOG_FILE 2>&1) || exit
    curl https://raw.githubusercontent.com/TumbleOwlee/neovim-config/main/init.lua > ~/.config/nvim/init.lua 2>>$LOG_FILE || exit

    # Install neovim plugins
    notify "Install neovim plugins.."
    nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerInstall'
fi

# Install docker
resp=$(ask "Install docker? [Y/n]" "Y")
if [ "_$resp" != "_n" ] && [ "_$resp" != "_N" ]; then
    info "Install docker"
    notify "Execute 'apt install'"
    sudo apt install -y docker docker-compose >>$LOG_FILE 2>&1 || exit
    notify "Add user to docker group."
    sudo groupadd docker >>$LOG_FILE 2>&1
    sudo usermod -aG docker $USER >>$LOG_FILE 2>&1 || exit
fi
