#!/bin/bash
set -euo pipefail

METADATA="$HOME/.local/share/app-installer/installed.json"
mkdir -p "$(dirname "$METADATA")"
[[ -f "$METADATA" ]] || echo "{}" > "$METADATA"

# --- Dependencies Check ---
# Added ImageMagick and xprop (for class detection)
for dep in zenity tar sudo jq magick xprop; do
    if ! command -v "$dep" &>/dev/null; then
        notify-send "Installer Error" "$dep is required. Please install it."
        echo "$dep is required. Install it first."
        exit 1
    fi
done

clean_name() {
    local name="$1"
    # Remove common architecture/platform suffixes
    name=$(echo "$name" | sed -E 's/(-linux|-x64|-win64|-macos)//g')
    # Remove version numbers (v1.2.3, -1.0, etc)
    name=$(echo "$name" | sed -E 's/[-_]?[0-9]+(\.[0-9]+)*$//')
    # Capitalize first letter
    [[ ${name:0:1} =~ [a-zA-Z] ]] && name="${name^}"
    echo "$name"
}

# -------------------------------
# File chooser
TAR_FILE=$(zenity --file-selection \
    --title="Select application archive" \
    --filename="$HOME/Downloads/" \
    --file-filter="Archives | *.tar.gz *.tgz *.tar.xz" || echo "")

[[ -z "$TAR_FILE" ]] && exit 0

case "$TAR_FILE" in
    *.tar.gz|*.tgz) TAR_OPTS="xvzf" ;;
    *.tar.xz)       TAR_OPTS="xvJf" ;;
    *) notify-send "Installer" "Unsupported archive type." --expire-time=3000; exit 1 ;;
esac

# Progress bar for extraction
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

(
    echo "10"; echo "# Extracting archive..."
    tar "$TAR_OPTS" "$TAR_FILE" -C "$TMP_DIR"
    echo "100"; echo "# Extraction complete"
) | zenity --progress --title="Installing..." --auto-close --pulsate

EXTRACTED_DIR=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)
[[ -z "$EXTRACTED_DIR" ]] && notify-send "Installer" "No folder found in archive." && exit 1

RAW_NAME=$(basename "$EXTRACTED_DIR")
APP_NAME=$(clean_name "$RAW_NAME")
INSTALL_DIR="/opt/$RAW_NAME"

# Confirm installation
zenity --question --text="Install <b>$APP_NAME</b> into <b>$INSTALL_DIR</b>?" || exit 0

# Sudo operations
# (Doing this early prevents sudo timeout during UI selection)
if [ -d "$INSTALL_DIR" ]; then
    if zenity --question --text="Directory $INSTALL_DIR exists. Overwrite?"; then
        sudo rm -rf "$INSTALL_DIR"
    else
        exit 0
    fi
fi
sudo mv "$EXTRACTED_DIR" "$INSTALL_DIR"

# -------------------------------
# IMPROVED: Executable Selection using Arrays
# We look for files that are executable
cd "$INSTALL_DIR"
# Find executables, exclude common noise like .so files or hidden files
# Removed ! -name "*.sh" because many apps (PyCharm, etc) use .sh wrappers
mapfile -t EXE_ARRAY < <(find . -maxdepth 2 -type f -executable ! -name "*.so*" ! -name ".*" | sed 's|^\./||')

if [ ${#EXE_ARRAY[@]} -eq 0 ]; then
    # Fallback if strict filter found nothing
    mapfile -t EXE_ARRAY < <(find . -maxdepth 2 -type f -executable | sed 's|^\./||')
fi

if [ ${#EXE_ARRAY[@]} -eq 0 ]; then
    notify-send "Installer Error" "No executable files found in archive."
    exit 1
fi

# Pass array directly to zenity to handle spaces correctly
# "|| echo" prevents script crash if user cancels (exit code 1)
SELECTED_EXE=$(zenity --list \
    --title="Select Executable" \
    --text="Which file starts the application?" \
    --column="Executables" \
    --height=400 \
    "${EXE_ARRAY[@]}" || echo "")

[[ -z "$SELECTED_EXE" ]] && exit 0

FULL_EXE_PATH="$INSTALL_DIR/$SELECTED_EXE"
LINK_PATH="/usr/local/bin/$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"

# Create Symlink
sudo ln -sf "$FULL_EXE_PATH" "$LINK_PATH"

# -------------------------------
# IMPROVED: Icon Selection
# Find images, sort by depth (shortest path/shallowest file first)
# This prevents picking up hundreds of plugin icons deep in subfolders before the main icon
# -printf '%d\t%p\n': Print depth level, tab, then full path
# sort -n: Sort by depth (shallowest first)
# cut -f2-: Remove the depth number
mapfile -t ICON_ARRAY < <(find "$INSTALL_DIR" -type f \( -iname "*.png" -o -iname "*.svg" -o -iname "*.ico" \) -printf '%d\t%p\n' | sort -n | cut -f2- | head -n 50)

ICON_PATH=""
if [ ${#ICON_ARRAY[@]} -gt 0 ]; then
    SELECTED_ICON=$(zenity --list \
        --title="Select Icon" \
        --text="Choose an icon for the shortcut" \
        --column="Icon Files" \
        --height=400 \
        "${ICON_ARRAY[@]}" || echo "")
    
    ICON_PATH="$SELECTED_ICON"
fi

# Resize icon if selected (handling .ico conversion too if magick supports it)
FINAL_ICON_PATH=""
if [[ -n "$ICON_PATH" ]]; then
    # Copy icon to standard location to avoid permission issues
    ICON_EXT="${ICON_PATH##*.}"
    FINAL_ICON_NAME="$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-').png"
    HOME_ICON_DIR="$HOME/.local/share/icons"
    mkdir -p "$HOME_ICON_DIR"
    FINAL_ICON_PATH="$HOME_ICON_DIR/$FINAL_ICON_NAME"
    
    magick "$ICON_PATH" -resize 256x256 "$FINAL_ICON_PATH"
fi


# -------------------------------
# NEW: StartupWMClass Detection Logic
# -------------------------------
WM_CLASS=""
if zenity --question --text="<b>Do you want to detect the Window Class?</b>\n\nThis fixes the issue where the Dock shows a generic gear icon instead of the app icon when running.\n\n(Requires launching the app now)"; then
    
    notify-send "Installer" "Launching $APP_NAME. Please wait for the window to appear..."
    
    # Run app in background, disowned so it doesn't block
    "$FULL_EXE_PATH" &
    APP_PID=$!
    
    # Give user instruction
    zenity --info --text="1. Wait for the app to open.\n2. Click OK below.\n3. Your cursor will turn into a <b>crosshair</b>.\n4. Click on the application window."
    
    # Capture class using xprop (Works on XWayland, which most tarballs use)
    # We use awk to grab the second string which is usually the Capitalized class name
    DETECTED_CLASS=$(xprop WM_CLASS | awk -F '"' '{print $4}')
    
    if [[ -n "$DETECTED_CLASS" ]]; then
        WM_CLASS="$DETECTED_CLASS"
        notify-send "Success" "Detected Class: $WM_CLASS"
    else
        notify-send "Error" "Could not detect class. Using default name."
        WM_CLASS="$APP_NAME"
    fi

    # Kill the temporary app instance
    kill "$APP_PID" 2>/dev/null || true
fi


# Create .desktop file
if zenity --question --text="Create Menu Shortcut?"; then
    TERMINAL=false
    if zenity --question --text="Does this app need a terminal?"; then
        TERMINAL=true
    fi

    DESKTOP_DIR="$HOME/.local/share/applications"
    mkdir -p "$DESKTOP_DIR"
    DESKTOP_FILE="$DESKTOP_DIR/$(echo "$APP_NAME" | tr ' ' '-').desktop"

    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Exec=$LINK_PATH
Icon=${FINAL_ICON_PATH:-utilities-terminal}
Terminal=$TERMINAL
Categories=Utility;Application;
StartupWMClass=${WM_CLASS}
EOF
    chmod +x "$DESKTOP_FILE"
    
    # Refresh GNOME database
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

# -------------------------------
# Update metadata
jq --arg app "$APP_NAME" \
   --arg folder "$INSTALL_DIR" \
   --arg symlink "$LINK_PATH" \
   --arg desktop "${DESKTOP_FILE:-}" \
   '.[$app] = {folder: $folder, symlink: $symlink, desktop: $desktop}' \
   "$METADATA" > "${METADATA}.tmp" && mv "${METADATA}.tmp" "$METADATA"

notify-send "Installer" "$APP_NAME installed successfully!"