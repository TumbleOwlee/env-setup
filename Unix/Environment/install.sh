#!/bin/bash

# Get location of script to allow call from any location
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Install all required tools
sudo pacman -Syu --needed --noconfirm < "${SCRIPT_DIR}/packages.txt"

# Install default environment configuration
cp -r "${SCRIPT_DIR}/.config" ~/.config
cp -r "${SCRIPT_DIR}/.screenlayout" ~/.screenlayout
cp -r "${SCRIPT_DIR}/.gtkrc-2.0" ~/.screenlayout
