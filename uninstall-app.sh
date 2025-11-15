#!/bin/bash
set -euo pipefail

METADATA="$HOME/.local/share/app-installer/installed.json"
mkdir -p "$(dirname "$METADATA")"
touch "$METADATA"

if [[ ! -s "$METADATA" ]]; then
    notify-send "Uninstaller" "No apps recorded for uninstall." --expire-time=3000
    exit 0
fi

APPS=($(jq -r 'keys[]' "$METADATA"))
SELECTED_APP=$(zenity --list --title="Select app to uninstall" --column="Installed Apps" "${APPS[@]}")
[[ -z "$SELECTED_APP" ]] && exit 0

# Retrieve info from metadata
INSTALL_DIR=$(jq -r --arg app "$SELECTED_APP" '.[$app].folder' "$METADATA")
SYMLINK=$(jq -r --arg app "$SELECTED_APP" '.[$app].symlink' "$METADATA")
DESKTOP_FILE=$(jq -r --arg app "$SELECTED_APP" '.[$app].desktop' "$METADATA")

# Folder removal
if [[ -d "$INSTALL_DIR" ]]; then
    zenity --question --text="Delete installation folder?\n$INSTALL_DIR" && sudo rm -rf "$INSTALL_DIR"
else
    zenity --question --text="Folder missing. Remove remaining components?" && :
fi

# Symlink removal
[[ -L "$SYMLINK" ]] && zenity --question --text="Delete symlink?\n$SYMLINK" && sudo rm -f "$SYMLINK"

# Desktop launcher removal
[[ -f "$DESKTOP_FILE" ]] && zenity --question --text="Delete desktop launcher?\n$DESKTOP_FILE" && rm -f "$DESKTOP_FILE"

# Remove entry from metadata
jq "del(.\"$SELECTED_APP\")" "$METADATA" > "${METADATA}.tmp" && mv "${METADATA}.tmp" "$METADATA"

notify-send "Uninstaller" "$SELECTED_APP uninstalled." --expire-time=3000
