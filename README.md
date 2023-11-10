# Environment Setup

This repository contains various scripts and configuration that I use in my various environments - private or work, bare metal or virtual machine. 
I created this collection since I'm usally working with various virtual machine and I want to have my environment set as fast as possible while providing the same user experience on each of them.

## Set up Unix Environment

The script `./unix/setup.sh` provides a simple but clear entry point to setup any Unix environment (currently arch and ubuntu is supported). Everything can be set up by executing the following command - an internet connection is required since the script will get other scripts and configurations from this repository.

```bash
bash -c "bash <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/setup.sh 2>/dev/null)" 
```

If you are behind a proxy, keep in mind to set `http_proxy` and `https_proxy` accordingly. Currently no offline installation is supported.

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
