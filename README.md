# Setup Environments

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
