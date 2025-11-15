#!/bin/bash
set -euo pipefail

# -------------------------------
# Dependencies: zenity, tar, sudo, convert (optional)
# -------------------------------
if ! command -v zenity &>/dev/null; then
    echo "Zenity is required for GUI prompts. Install it first (sudo dnf install zenity)."
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
# Select archive file
# -------------------------------
TAR_FILE=$(zenity --file-selection \
    --title="Select application tar.gz or tar.xz" \
    --file-filter="Archives | *.tar.gz *.tgz *.tar.xz")
if [[ -z "$TAR_FILE" ]]; then
    zenity --error --text="No file selected. Exiting."
    exit 1
fi

# Determine tar options
case "$TAR_FILE" in
    *.tar.gz|*.tgz) TAR_OPTS="xvzf" ;;
    *.tar.xz)       TAR_OPTS="xvJf" ;;
    *) zenity --error --text="Unsupported archive type"; exit 1 ;;
esac

# -------------------------------
# Extract to temporary directory
# -------------------------------
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT
tar "$TAR_OPTS" "$TAR_FILE" -C "$TMP_DIR"

EXTRACTED_DIR=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)
if [[ -z "$EXTRACTED_DIR" ]]; then
    zenity --error --text="No folder found in archive"
    exit 1
fi

RAW_NAME=$(basename "$EXTRACTED_DIR")
APP_NAME=$(clean_name "$RAW_NAME")
INSTALL_DIR="/opt/$RAW_NAME"

# -------------------------------
# Confirm installation directory
# -------------------------------
if ! zenity --question --text="Install $APP_NAME into $INSTALL_DIR?"; then
    exit 0
fi

sudo rm -rf "$INSTALL_DIR"
sudo mv "$EXTRACTED_DIR" "$INSTALL_DIR"

# -------------------------------
# Select main executable
# -------------------------------
EXECUTABLES=($(find "$INSTALL_DIR" -maxdepth 1 -type f -executable))
SELECTED_EXE=""
for exe in "${EXECUTABLES[@]}"; do
    exe_name=$(basename "$exe")
    if zenity --question --text="Is this the correct executable?\n$exe_name"; then
        SELECTED_EXE="$exe"
        break
    fi
done

if [[ -n "$SELECTED_EXE" ]]; then
    LINK_PATH="/usr/local/bin/$APP_NAME"
    sudo ln -sf "$SELECTED_EXE" "$LINK_PATH"
else
    zenity --warning --text="No executable selected. Skipping symlink."
fi

# -------------------------------
# GUI launcher creation
# -------------------------------
if zenity --question --text="Do you want to create a GUI launcher for $APP_NAME?"; then
    TERMINAL=false
    if [[ -n "$SELECTED_EXE" ]]; then
        if zenity --question --text="Should this application run in a terminal?"; then
            TERMINAL=true
        fi
    fi

    DESKTOP_DIR="$HOME/.local/share/applications"
    mkdir -p "$DESKTOP_DIR"
    DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME.desktop"

    # Icon selection with preview
    ICON_PATH=""
    ICONS=($(find "$INSTALL_DIR" -type f \( -iname "*.png" -o -iname "*.svg" \)))
    for icon in "${ICONS[@]}"; do
        TMP_ICON="$icon"
        if command -v magick &>/dev/null; then
            TMP_ICON=$(mktemp --suffix=.png)
            magick "$icon" -resize 200x200\! "$TMP_ICON"
        fi

        if zenity --question --text="Use this icon?" --icon="$TMP_ICON"; then
            ICON_PATH="$icon"
            [[ -f "$TMP_ICON" && "$TMP_ICON" != "$icon" ]] && rm -f "$TMP_ICON"
            break
        else
            [[ -f "$TMP_ICON" && "$TMP_ICON" != "$icon" ]] && rm -f "$TMP_ICON"
        fi
    done

    # Create .desktop file
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

notify-send "Installer" "Installation of $APP_NAME complete." --expire-time=3000
