#!/bin/bash
set -euo pipefail

APP_NAME="sampleapp"
TMP_DIR=$(mktemp -d)
echo "Creating sample app in $TMP_DIR/$APP_NAME"

mkdir -p "$TMP_DIR/$APP_NAME"

# --- Main executable ---
cat << 'EOF' > "$TMP_DIR/$APP_NAME/run.sh"
#!/bin/bash
echo "Sample App launched!"
EOF
chmod +x "$TMP_DIR/$APP_NAME/run.sh"

# --- Helper executable ---
cat << 'EOF' > "$TMP_DIR/$APP_NAME/helper"
#!/bin/bash
echo "This is a helper executable."
EOF
chmod +x "$TMP_DIR/$APP_NAME/helper"

# --- Simple icon (dummy PNG) ---
# Using ImageMagick to generate a simple icon if installed
if command -v convert &>/dev/null; then
    convert -size 128x128 xc:skyblue -gravity center -pointsize 20 -annotate 0 "S" "$TMP_DIR/$APP_NAME/icon.png"
else
    # fallback: create an empty placeholder
    touch "$TMP_DIR/$APP_NAME/icon.png"
fi

# --- Package into tar.gz ---
cd "$TMP_DIR"
tar -czvf "$APP_NAME.tar.gz" "$APP_NAME"

# Move tar.gz to current directory
mv "$APP_NAME.tar.gz" "$OLDPWD/"

echo "Sample application created: $OLDPWD/$APP_NAME.tar.gz"
echo "Folder structure:"
tree "$TMP_DIR/$APP_NAME" || ls -R "$TMP_DIR/$APP_NAME"
