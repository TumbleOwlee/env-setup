# Environment Setup

This repository contains various scripts and configuration that I use in my various environments - private or work, bare metal or virtual machine. 
I created this collection since I'm usally working with various virtual machine and I want to have my environment set as fast as possible while providing the same user experience on each of them. Everything is done using only Bash since it's the common base of every Unix install. Of course it would be fancier using e.g. Python's full capabilities.

## Set up Unix Environment

The script `./unix/setup.sh` provides a simple but clear entry point to setup any Unix environment (currently arch and ubuntu is supported). Everything can be set up by executing the following command - an internet connection is required since the script will get other scripts and configurations from this repository.

```bash
bash -c "bash <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/setup.sh 2>/dev/null)" 
```

If you are behind a proxy, keep in mind to set `http_proxy` and `https_proxy` accordingly. Currently no offline installation is supported. The command only uses `bash -c` calling `bash` because the command should work by copy&paste in any shell you are currently using.

In case you cloned the repository and want to execute the script `./Unix/setup.sh` directly using only local files, just use the following command instead.

```bash
DEBUG=y ./Unix/setup.sh
```

This will source the other scripts instead of using `curl` to retrieve the files from the repository on Github.

While executing you can choose the parts you like to install and skip any you don't need. Currently the following parts are available to be installed:

* Alacritty
* Fish Shell
* Tmux
* Neovim
    - NerdFonts
    - Neovim Lua LSP
    - Neovim Python LSP
* Docker
* Rust Environment
    - Rustup
    - Rust-Src
    - Rust-Analyzer
    - Neovim Rust LSP
* C++ Environment
    - Clang
    - GCC
    - CMake
    - Neovim Clang LSP
* Bioinformatics Environment
    - snakemake

As available the configurations from this repository are also installed. In case of Neovim, the configuration is taken from [here](https://github.com/TumbleOwlee/neovim-config). I will add additional parts as time goes on and my demands change.

## Set up Windows Environment

Since I'm mainly developing on Unix based operating systems, this repository doesn't contain any script to setup a full environment on a Windows host. Instead it contains scripts to provide helper functions to simplify the interaction with Unix systems.

To get the provided helper function in your PowerShell environment, just install the files in `./windows/Scripts` into `%USERPROFILE%\Scripts` and `./windows/Documents/PowerShell` into `%USERPROFILE%\Documents\PowerShell`.

```ps
mkdir $home\Scripts

# Wrapper to provide `Connect-SSH` in PowerShell for easy SSH connection
curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Windows/Scripts/connect.py -o $home\Scripts\connect.py

# Install PowerShell profile that provides the aliases for all functions
curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Windows/Documents/WindowsPowerShell/profile.ps1 -o $home\Documents\WindowsPowerShell\profile.ps1
```

If your Windows system has some more restriction in place (e.g. your home directory is on a network drive), the PowerShell script may not load at all. A quick and dirty solution for that is to place the `profile.ps1` into `C:\Windows\System32\WindowsPowerShell\v1.0` instead of `%USERPROFILE%\Documents\PowerShell`.

## Using Bash

The provided setup installs `fish` as the default shell. But if you're using other hosts - where you are unable to install/use `fish` - you can get the same shell prompt by adding the following code into your `~/.bashrc`. 

```bash
colorize_exit_code() {
        exit_code="$1"
        local red=$(tput setaf 1)
        local green=$(tput setaf 2)
        local reset=$(tput sgr0)
        if [ "$exit_code" == "0" ] || [ "$exit_code" == "" ]; then
                printf '\001%s\002[0]\001%s\002' "$green" "$reset"
        else
                printf '\001%s\002[%s]\001%s\002' "$red" "$exit_code" "$reset"
        fi
}

# Most likely such an if-else block will already be present in your .bashrc. Just replace it with this.
if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}(\[\033[0;33m\]\h\[\033[m\]|\[\033[0;34m\]\u\[\033[m\]|\[\033[0;33m\]\w\[\033[m\])$(colorize_exit_code $?)> '
else
    PS1='${debian_chroot:+($debian_chroot)}(\h|\u|\w)[$?]> '
fi
```
