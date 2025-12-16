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

# Create/Reset strategy config if not exists - write default working config
if [ ! -f "$TARGET_DIR/config_custom" ]; then
    cat > "$TARGET_DIR/config_custom" <<'CONFIGEOF'
MODE_FILTER=autohostlist
TPWS_ENABLE=1
TPWS_SOCKS_ENABLE=1
TPWS_PORTS=80,443
INIT_APPLY_FW=1
DISABLE_IPV6=1
GZIP_LISTS=0
GETLIST=get_refilter_domains.sh
TPWS_OPT="
--filter-tcp=80 --methodeol <HOSTLIST> --new
--filter-tcp=443 --split-pos=1,midsld --disorder <HOSTLIST>
"
CONFIGEOF
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
touch "$TARGET_DIR/ipset/zapret-hosts.txt"

# Make helper scripts executable
chmod +x "$TARGET_DIR/ipset/"*.sh

# Try to download Re-filter list (contains YouTube and other needed domains)
echo "Downloading Re-filter hostlist..."
# Run in subshell to not change script cwd, ignore errors to not break install
(export GZIP_LISTS=0 && cd "$TARGET_DIR/ipset" && ./get_refilter_domains.sh) || echo "Warning: Failed to download Re-filter list. Using empty list."
chmod 644 "$TARGET_DIR/ipset/"*.txt

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
        <string>start</string>
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
