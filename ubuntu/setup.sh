#!/bin/bash

# Banner function
function banner {
    str="$1"
    len=${#str}
    echo -e -n "\n\e[0;32m######"
    for i in $(seq $len); do
        echo -n "#"
    done
    echo ""
    echo "## $str ##"
    echo -n "######"
    for i in $(seq $len); do
        echo -n "#"
    done
    echo -e "\e[0m\n"
}

# Update and upgrade
banner "Update and Upgrade"
sudo apt update
sudo apt upgrade -y

# Install requirements
banner "Install Requirements"
sudo apt install -y git curl

# Install alacritty
banner "Install Alacritty"
sudo add-apt-repository ppa:aslatter/ppa -y
sudo apt update
sudo apt install -y alacritty

# Create alacritty configuration
mkdir -p ~/.config/alacritty >/dev/null 2>&1
echo "window:" > ~/.config/alacritty/alacritty.yml
echo "  opacity: 0.9" >> ~/.config/alacritty/alacritty.yml
echo "font:" >> ~/.config/alacritty/alacritty.yml
echo "  size: 8.0" >> ~/.config/alacritty/alacritty.yml

# Install fish
banner "Install Fish Shell"
sudo apt install -y fish
sudo chsh -s $(which fish)
sudo usermod -s /usr/bin/fish $(whoami)

# Create fish configuration
echo -e "function fish_greeting\nend" > ~/.config/fish/functions/fish_greeting.fish
echo -e "function fish_prompt --description 'Write out the prompt'\n    set -l laststatus \$status\n\n    set -l git_info\n    if set -l git_branch (command git symbolic-ref HEAD 2>/dev/null | string replace refs/heads/ '')\n        set git_branch (set_color -o blue)\"\$git_branch\"\n        set -l git_status\n        if not command git diff-index --quiet HEAD --\n            if set -l count (command git rev-list --count --left-right \$upstream...HEAD 2>/dev/null)\n                echo \$count | read -l ahead behind\n                if test \"\$ahead\" -gt 0\n                    set git_status \"\$git_status\"(set_color red)⬆\n                end\n                if test \"\$behind\" -gt 0\n                    set git_status \"\$git_status\"(set_color red)⬇\n                end\n            end\n            for i in (git status --porcelain | string sub -l 2 | sort | uniq)\n                switch \$i\n                    case \".\"\n                        set git_status \"\$git_status\"(set_color green)'+'\n                    case \" D\"\n                        set git_status \"\$git_status\"(set_color red)'x'\n                    case \"*M*\"\n                        set git_status \"\$git_status\"(set_color green)'*'\n                    case \"*R*\"\n                        set git_status \"\$git_status\"(set_color purple)'>'\n                    case \"*U*\"\n                        set git_status \"\$git_status\"(set_color brown)'='\n                    case \"??\"\n                        set git_status \"\$git_status\"(set_color red)'!='\n                end\n            end\n        else\n            set git_status (set_color green):\n        end\n        set git_info \"(git\$git_status\$git_branch\"(set_color white)\")\"\n    end\n\n    # Disable PWD shortening by default.\n    set -q fish_prompt_pwd_dir_length\n    or set -lx fish_prompt_pwd_dir_length 0\n\n    set_color -b black\n    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s' (set_color -o white) '(' (set_color brcyan) \$USER (set_color white) '|' (set_color yellow) (prompt_pwd) (set_color white) \$git_info (set_color white) ')' (set_color white)\n    if test \$laststatus -eq 0\n        printf \"%s[0]%s>%s \" (set_color -o green) (set_color white) (set_color normal)\n    else\n        printf \"%s[%s]%s>%s \" (set_color -o red) \$laststatus (set_color white) (set_color normal)\n    end\nend" > ~/.config/fish/functions/fish_prompt.fish

# Install tmux
banner "Install Tmux"
sudo apt install -y tmux

# Create tmux configuration
echo "set -g status off" > ~/.tmux.conf

# Install neovim
banner "Install Neovim"
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install -y neovim

# Get neovim configuration
mkdir -p ~/.config/nvim >/dev/null 2>&1
git clone https://github.com/wbthomason/packer.nvim ~/.local/share/nvim/site/pack/packer/start/packer.nvim
curl https://raw.githubusercontent.com/TumbleOwlee/neovim-config/main/init.lua > ~/.config/nvim/init.lua

# Install neovim plugins
banner "Install Neovim Config"
nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerInstall'

# Install docker
read -p "Install docker? " value
if [ "_$value" != "_n" ] && [ "_$value" != "_N" ]; then
    sudo apt install -y docker docker-compose
fi
