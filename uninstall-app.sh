#!/bin/bash
set -euo pipefail

# -------------------------------
# Dependencies: zenity
# -------------------------------
if ! command -v zenity &>/dev/null; then
    echo "Zenity is required. Install it first (sudo dnf install zenity)."
    exit 1
fi

# -------------------------------
# Utility: Clean app name
# -------------------------------
clean_name() {
    local name="$1"
    name="${name%-linux-x64}"
    name="${name%-linux}"
    name="${name%-x64}"
    name="${name%-win64}"
    name="${name%-macos}"
    name=$(echo "$name" | sed -E 's/[-_][0-9]+(\.[0-9]+)*$//')
    [[ ${name:0:1} =~ [a-zA-Z] ]] && name="${name^}"
    echo "$name"
}

# -------------------------------
# Ask user to select installation folder
# -------------------------------
INSTALL_DIR=$(zenity --file-selection --directory --title="Select the application folder to uninstall" --filename="/opt/")
if [[ -z "$INSTALL_DIR" ]]; then
    zenity --error --text="No folder selected. Exiting."
    exit 1
fi

RAW_NAME=$(basename "$INSTALL_DIR")
APP_NAME=$(clean_name "$RAW_NAME")
SYMLINK="/usr/local/bin/$APP_NAME"
DESKTOP_FILE="$HOME/.local/share/applications/$APP_NAME.desktop"

notify-send "Uninstaller" "Preparing to uninstall $APP_NAME" --expire-time=3000

# -------------------------------
# Remove installation folder
# -------------------------------
if [[ -d "$INSTALL_DIR" ]]; then
    if zenity --question --text="Delete installation directory?\n$INSTALL_DIR"; then
        sudo rm -rf "$INSTALL_DIR"
        notify-send "Uninstaller" "Deleted $INSTALL_DIR" --expire-time=3000
    else
        notify-send "Uninstaller" "Skipped $INSTALL_DIR" --expire-time=3000
    fi
else
    zenity --warning --text="Installation directory not found: $INSTALL_DIR"
fi

# -------------------------------
# Remove symlink
# -------------------------------
if [[ -L "$SYMLINK" ]]; then
    if zenity --question --text="Delete symlink?\n$SYMLINK"; then
        sudo rm -f "$SYMLINK"
        notify-send "Uninstaller" "Deleted $SYMLINK" --expire-time=3000
    else
        notify-send "Uninstaller" "Skipped $SYMLINK" --expire-time=3000
    fi
else
    zenity --warning --text="Symlink not found: $SYMLINK"
fi

# -------------------------------
# Remove desktop launcher
# -------------------------------
if [[ -f "$DESKTOP_FILE" ]]; then
    if zenity --question --text="Delete desktop launcher?\n$DESKTOP_FILE"; then
        rm -f "$DESKTOP_FILE"
        notify-send "Uninstaller" "Deleted $DESKTOP_FILE" --expire-time=3000
    else
        notify-send "Uninstaller" "Skipped $DESKTOP_FILE" --expire-time=3000

    fi
else
    zenity --warning --text="Desktop launcher not found: $DESKTOP_FILE"
fi

notify-send "Uninstaller" "Uninstallation of $APP_NAME complete." --expire-time=3000

