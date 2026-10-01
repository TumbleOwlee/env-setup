# Environment Setup

[![Lint](https://github.com/TumbleOwlee/env-setup/actions/workflows/lint.yml/badge.svg)](https://github.com/TumbleOwlee/env-setup/actions/workflows/lint.yml)

This repository contains various scripts and configuration that I use in my various environments - private or work, bare metal or virtual machine.
I created this collection since I'm usually working with various virtual machines and I want to have my environment set as fast as possible while providing the same user experience on each of them. Everything is done using only Bash since it's the common base of every Unix install. Of course it would be fancier using e.g. Python's full capabilities.

## Set up Unix Environment

`Unix/setup.sh` is the entry point. It detects the distribution from `/etc/os-release` and runs `Unix/Arch/setup.sh` or `Unix/Debian/setup.sh`, which in turn use the shared `Unix/common.sh` and `Unix/steps.sh`.

**Supported:** Arch Linux, Ubuntu LTS (22.04+), Debian stable. Running as root (e.g. in containers) works, otherwise `sudo` is required.

**Prerequisites:** `bash` and an internet connection. `curl` is installed by `setup.sh` if it is missing. Run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/setup.sh)
```

Flags can be appended to the command, e.g. `bash <(curl -fsSL ...) --noconfirm --skip=docker`.

If you are behind a proxy, set `http_proxy` and `https_proxy` accordingly (the setup asks `Behind a proxy?` and aborts if they are empty). Offline installation is not supported.

If you cloned the repository, use only local files with:

```bash
./Unix/setup.sh --debug
```

### Flags

| Flag | Effect |
| --- | --- |
| `-d`, `--debug` | Use the files of the local checkout instead of downloading them. |
| `-n`, `--noconfirm` | Answer every prompt with its default (also makes apt non-interactive on Debian/Ubuntu). |
| `--skip=<name>` | Skip a part. Can be given multiple times. |

Names for `--skip`: `fish`, `tmux`, `neovim`, `docker`, `rust`, `alacritty`, `cxx`, `delta`, `mise`, `scripts`, `fonts`. `neovim` skips both the binary and the configuration.

The environment variable `ENV_SETUP_URL` replaces the base URL (default `https://raw.githubusercontent.com/TumbleOwlee/env-setup/main`) that files are downloaded from, e.g. for a fork or a mirror.

### Prompts

Every optional part asks `Install <part>? [Y/n]` (default yes). Besides that the setup asks:

* `Behind a proxy? [y/N]`
* `Update and upgrade? [Y/n]`
* `Use upstream release instead of packaged <tool> <version>? [y/N]` for zoxide, rustup, delta, mise and (Debian/Ubuntu) neovim. The default is the distribution package. If the package manager has no such package, the upstream release is used without asking.
* `Install Conan? [Y/n]` as part of the C++ environment
* `Replace existing nvim configuration? [Y/n]` if `~/.config/nvim` exists and is not a git checkout

If a command fails you are asked whether to show the log and whether to retry or terminate. With `--noconfirm` a failure prints the log tail and aborts.

**Neovim on Debian/Ubuntu:** the neovim configuration requires Neovim 0.12 or newer. If the packaged neovim is older, the upstream prebuilt release is installed into `/opt/nvim` (linked to `/usr/local/bin/nvim`) without asking. Otherwise you are asked whether to use the package or the upstream release; `--noconfirm` picks the package. If the installed neovim is too old, the plugin synchronization is skipped with a warning. On Arch the package is used.

## Packages

Package names are mapped per distribution (e.g. `fd-find` and `ninja-build` on Debian). The steps are idempotent, so the script can be run again to update.

**Always installed:**
* Git, Python (+ `python3-venv` on Debian), pipx, Unzip, Wget, Less, Curl, GPG, FZF
* Zoxide (package or upstream installer)

On Arch additionally `base-devel` and `yay` (built from the AUR, as a temporary build user when running as root).

**Optional parts:**

| Part | Installs |
| --- | --- |
| `fish` | Fish shell as login shell, prompt/greeting/`colored_cat` functions |
| `tmux` | tmux and its configuration |
| `neovim` | Neovim, ninja, [neovim-config](https://github.com/TumbleOwlee/neovim-config) (plugins and the LSPs `lua-language-server`, `python-lsp-server` via Mason) |
| `fonts` | FiraCode Nerd Font (asked as part of `neovim` and `alacritty`) |
| `docker` | docker, compose (+ buildx if available), user added to the `docker` group |
| `rust` | rustup with the stable toolchain, `rust-src`, `rust-analyzer`, libclang, `cross`, `tree-sitter-cli` |
| `cxx` | clang, gcc, cmake, lldb (+ `clang-format` on Debian/Ubuntu), optionally Conan via pipx |
| `alacritty` | Alacritty and its configuration. Packaged on Arch, built from source on Debian/Ubuntu (this requires rust and installs it even with `--skip=rust`) |
| `delta` | git-delta and its git configuration |
| `mise` | mise |
| `scripts` | `git-sync`, `git-check`, `git-hooks`, `dbg`, `finance`, `win-move` in `~/.local/bin` |

### Written files and backups

Files managed by the setup are rewritten on every run and must not be edited.

| File | Content |
| --- | --- |
| `~/.config/env-setup/bashrc.sh` | PATH (`~/.local/bin`, `~/.cargo/bin`) and zoxide for bash. Sourced from one line the setup appends to `~/.bashrc`. |
| `~/.config/fish/conf.d/env-setup.fish` | The same for fish, plus the `cat` alias and `vim`/`vi`/`v` abbreviations for nvim. |
| `~/.config/fish/functions/` | `fish_greeting`, `fish_prompt`, `colored_cat`. |
| `~/.config/tmux/env-setup.local.conf` | Sets fish as tmux `default-shell`. Sourced by `~/.tmux.conf`. |
| `~/.tmux.conf` | Repository configuration. |
| `~/.config/git/env-setup.gitconfig` | Delta settings, added to the global git config through an `include.path` entry. |
| `~/.config/delta/themes.gitconfig` | Delta themes. |
| `~/.config/alacritty/alacritty.toml` | Repository configuration. An old `alacritty.yml` is renamed. |
| `~/.config/nvim` | Clone of neovim-config, updated with `git pull --ff-only`. |
| `~/.local/share/fonts/FiraCode` | Nerd font. |

Before an existing file is replaced (`~/.tmux.conf`, `alacritty.toml`, `alacritty.yml`, a non-git `~/.config/nvim`) a copy is saved as `<file>.bak.<YYYYmmddHHMMSS>`. Blocks appended to `~/.bashrc` and `~/.config/fish/config.fish` by older versions of these scripts are removed automatically, after saving a backup of the file in the same way.

## Desktop Environment (bspwm, Arch)

`Unix/Environment/install.sh` installs the bspwm based desktop (bspwm, sxhkd, polybar, rofi, dunst, picom, ...). It is not part of `setup.sh`; run it separately on Arch from a checkout:

```bash
./Unix/Environment/install.sh
```

It installs the packages in `packages.txt` with pacman and the ones in `aur-packages.txt` with `yay` (only a warning if `yay` is missing), then copies `.config`, `.screenlayout`, `.backgrounds` and `.gtkrc-2.0` into your home directory, **overwriting existing files of the same name**.

Machine specific settings live in `~/.config/env-setup/local.conf`. The installer creates it from `Unix/Environment/local.conf.example` if it does not exist and never overwrites it. The file is sourced by bash and supports:

| Variable | Purpose |
| --- | --- |
| `BT_DEVICES` | Array of `'Name\|AA:BB:CC:DD:EE:FF'` entries for the rofi bluetooth menu |
| `WIN_MOVE_WIDTH`, `WIN_MOVE_HEIGHT` | Override the screen size detected by `win-move` |
| `MONITOR_PRIMARY` | Primary monitor name (`bspc query -M --names`) |
| `WLAN_IF` | Wireless interface for polybar |
| `BATTERY`, `ADAPTER` | Names under `/sys/class/power_supply` |
| `BACKLIGHT` | Device under `/sys/class/backlight` |

All overrides except `BT_DEVICES` are optional; unset values are auto-detected.

## Development

The workflow `.github/workflows/lint.yml` runs `shfmt -d -i 4` and `shellcheck -x` on all tracked shell scripts (`*.sh`, shell shebangs and `bspwmrc`). Use 4 spaces for indentation.

## Set up Windows Environment

Since I'm mainly developing on Unix based operating systems, this repository doesn't contain any script to setup a full environment on a Windows host. Instead it contains scripts to provide helper functions to simplify the interaction with Unix systems.

To get the provided helper functions in your PowerShell environment, install `Windows/Scripts/connect.py` into `%USERPROFILE%\Scripts` and `Windows/Documents/WindowsPowerShell/profile.ps1` into `%USERPROFILE%\Documents\WindowsPowerShell`.

```powershell
mkdir $home\Scripts
mkdir $home\Documents\WindowsPowerShell

# Wrapper to provide `Connect-SSH` in PowerShell for easy SSH connection
curl.exe -fsSL "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Windows/Scripts/connect.py" -o "$home\Scripts\connect.py"

# Install PowerShell profile that provides the aliases for all functions
curl.exe -fsSL "https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Windows/Documents/WindowsPowerShell/profile.ps1" -o "$home\Documents\WindowsPowerShell\profile.ps1"

# Disable Bing Search in start menu
Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" BingSearchEnabled 0
```

The repository also contains an Alacritty configuration for Windows in `Windows/AppData/Roaming/alacritty/alacritty.toml` (to be placed in `%APPDATA%\alacritty`).

Additionally it is advised to install the [`FiraCode Nerd Font`](https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip) if you use Alacritty with the provided configuration. It's also helpful in case you are using the provided `neovim` configuration, since it requires the patched font to display additional icons.

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
