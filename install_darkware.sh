#!/bin/bash
set -e
TARGET_DIR="/opt/darkware-zapret"

# Debug log
LOG="/tmp/darkware_install.log"
echo "Starting installation..." > "$LOG"

# Detect directory where this script resides
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SOURCE_DIR="$SCRIPT_DIR/zapret"

echo "Script Dir: '$SCRIPT_DIR'" >> "$LOG"
echo "Source Dir: '$SOURCE_DIR'" >> "$LOG"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory does not exist at $SOURCE_DIR" | tee -a "$LOG"
    exit 1
fi

echo "Installing to $TARGET_DIR..."

# Create dir
mkdir -p "$TARGET_DIR"

# Copy files (using dot syntax for reliable copying of content)
cp -R "$SOURCE_DIR/." "$TARGET_DIR/" || { echo "Copy failed" >> "$LOG"; exit 1; }

# Create/Reset strategy config if not exists
if [ ! -f "$TARGET_DIR/config_custom" ]; then
    echo "# Custom strategy config" > "$TARGET_DIR/config_custom"
fi
chmod 666 "$TARGET_DIR/config_custom"

# Hook custom config into main config if not already there
CONFIG_FILE="$TARGET_DIR/config"
if ! grep -q "config_custom" "$CONFIG_FILE"; then
    echo "" >> "$CONFIG_FILE"
    echo "# Load custom strategy from GUI" >> "$CONFIG_FILE"
    echo ". \"$TARGET_DIR/config_custom\"" >> "$CONFIG_FILE"
fi

# Create necessary directories
mkdir -p "$TARGET_DIR/ipset"
mkdir -p "$TARGET_DIR/init.d/macos"

# Initialize hostlist files to prevent startup errors
touch "$TARGET_DIR/ipset/zapret-hosts-user.txt"
touch "$TARGET_DIR/ipset/zapret-hosts-auto.txt"
touch "$TARGET_DIR/ipset/zapret-hosts-user-exclude.txt"

# Add dummy entry if user list is empty (best practice from install_easy.sh)
if [ ! -s "$TARGET_DIR/ipset/zapret-hosts-user.txt" ]; then
    echo "nonexistent.domain" >> "$TARGET_DIR/ipset/zapret-hosts-user.txt"
fi

# Executable permissions
xattr -d com.apple.quarantine -r "$TARGET_DIR" 2>/dev/null || true
chmod +x "$TARGET_DIR/init.d/macos/zapret"
chmod +x "$TARGET_DIR/tpws/tpws"

# Create Sudoers rule
# We use a separate file in /etc/sudoers.d/
SUDOERS_FILE="/etc/sudoers.d/darkware-zapret"
echo "Creating sudoers rule at $SUDOERS_FILE"
echo "ALL ALL=(ALL) NOPASSWD: $TARGET_DIR/init.d/macos/zapret" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"

# Setup LaunchDaemon for Autostart
PLIST_PATH="/Library/LaunchDaemons/com.darkware.zapret.plist"
echo "Creating LaunchDaemon at $PLIST_PATH"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.darkware.zapret</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/darkware-zapret/init.d/macos/zapret</string>
        <string>start-daemons</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/darkware-zapret.error.log</string>
    <key>StandardOutPath</key>
    <string>/tmp/darkware-zapret.out.log</string>
</dict>
</plist>
EOF

# Load the daemon
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load -w "$PLIST_PATH"

echo "Installation complete."
