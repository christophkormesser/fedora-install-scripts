#!/bin/bash
set -euo pipefail

METADATA="$HOME/.local/share/app-installer/installed.json"
mkdir -p "$(dirname "$METADATA")"
[[ -f "$METADATA" ]] || echo "{}" > "$METADATA"


# Dependencies
for dep in zenity tar sudo jq; do
    if ! command -v "$dep" &>/dev/null; then
        echo "$dep is required. Install it first."
        exit 1
    fi
done

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
# File chooser
TAR_FILE=$(zenity --file-selection \
    --title="Select application tar.gz or tar.xz" \
    --filename="$HOME/Downloads/" \
    --file-filter="Archives | *.tar.gz *.tgz *.tar.xz")

[[ -z "$TAR_FILE" ]] && notify-send "Installer" "No file selected." --expire-time=3000 && exit 1

case "$TAR_FILE" in
    *.tar.gz|*.tgz) TAR_OPTS="xvzf" ;;
    *.tar.xz)       TAR_OPTS="xvJf" ;;
    *) notify-send "Installer" "Unsupported archive type." --expire-time=3000; exit 1 ;;
esac

TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT
tar "$TAR_OPTS" "$TAR_FILE" -C "$TMP_DIR"

EXTRACTED_DIR=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)
[[ -z "$EXTRACTED_DIR" ]] && notify-send "Installer" "No folder found in archive." --expire-time=3000 && exit 1

RAW_NAME=$(basename "$EXTRACTED_DIR")
APP_NAME=$(clean_name "$RAW_NAME")
INSTALL_DIR="/opt/$RAW_NAME"

# Confirm installation
zenity --question --text="Install $APP_NAME into $INSTALL_DIR?" || exit 0

sudo rm -rf "$INSTALL_DIR"
sudo mv "$EXTRACTED_DIR" "$INSTALL_DIR"

# Executable selection
EXECUTABLES=($(find "$INSTALL_DIR" -maxdepth 1 -type f -executable))
SELECTED_EXE=""
for exe in "${EXECUTABLES[@]}"; do
    exe_name=$(basename "$exe")
    if zenity --question --text="Is this the correct executable?\n$exe_name"; then
        SELECTED_EXE="$exe"
        break
    fi
done

LINK_PATH="/usr/local/bin/$APP_NAME"
[[ -n "$SELECTED_EXE" ]] && sudo ln -sf "$SELECTED_EXE" "$LINK_PATH"

# Optional GUI launcher
if zenity --question --text="Create GUI launcher for $APP_NAME?"; then
    TERMINAL=false
    [[ -n "$SELECTED_EXE" ]] && zenity --question --text="Run in terminal?" && TERMINAL=true

    DESKTOP_DIR="$HOME/.local/share/applications"
    mkdir -p "$DESKTOP_DIR"
    DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME.desktop"

    ICON_PATH=""
    ICONS=($(find "$INSTALL_DIR" -type f \( -iname "*.png" -o -iname "*.svg" \)))
    for icon in "${ICONS[@]}"; do
        TMP_ICON="$icon"
        [[ -x "$(command -v magick)" ]] && TMP_ICON=$(mktemp --suffix=.png) && magick "$icon" -resize 200x200\! "$TMP_ICON"
        if zenity --question --text="Use this icon?" --icon="$TMP_ICON"; then
            ICON_PATH="$icon"
            [[ -f "$TMP_ICON" && "$TMP_ICON" != "$icon" ]] && rm -f "$TMP_ICON"
            break
        else
            [[ -f "$TMP_ICON" && "$TMP_ICON" != "$icon" ]] && rm -f "$TMP_ICON"
        fi
    done

    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Exec=$LINK_PATH
Icon=$ICON_PATH
Terminal=$TERMINAL
Categories=Utility;
EOF
    chmod +x "$DESKTOP_FILE"
fi

# -------------------------------
# Update metadata
jq --arg app "$APP_NAME" \
   --arg folder "$INSTALL_DIR" \
   --arg symlink "$LINK_PATH" \
   --arg desktop "$DESKTOP_FILE" \
   '.[$app] = {folder: $folder, symlink: $symlink, desktop: $desktop}' \
   "$METADATA" > "${METADATA}.tmp" && mv "${METADATA}.tmp" "$METADATA"

notify-send "Installer" "Installation of $APP_NAME complete." --expire-time=3000
