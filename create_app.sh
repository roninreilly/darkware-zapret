#!/bin/bash
set -e

APP_NAME="darkware zapret"
EXECUTABLE_NAME="DarkwareZapret"
BUNDLE_IDENTIFIER="com.darkware.zapret"
OUTPUT_DIR="."

echo "Building..."
swift build -c release

echo "Creating App Bundle..."
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources"

# Copy binary
cp ".build/release/$EXECUTABLE_NAME" "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

echo "Copying resources..."
cp -R "zapret_src" "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/zapret"
cp "install_darkware.sh" "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/"
cp "DarkwareZapret.icns" "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"

# Create Info.plist
cat > "$OUTPUT_DIR/$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <string>1.0.6</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/> <!-- This hides the app from the Dock (Tray-only app) -->
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# chmod
chmod +x "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
chmod +x "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/install_darkware.sh"

echo "App Bundle created at $OUTPUT_DIR/$APP_NAME.app"


echo "Creating DMG Installer..."
DMG_NAME="DarkwareZapret_Installer"
VOL_NAME="Darkware Zapret Installer"
STAGING_DIR="./dmg_staging"

# Clean up
rm -rf "$STAGING_DIR"
rm -f "$OUTPUT_DIR/$DMG_NAME.dmg"
rm -f "$OUTPUT_DIR/pack.temp.dmg"

# Prepare staging
mkdir -p "$STAGING_DIR"
cp -R "$OUTPUT_DIR/$APP_NAME.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create temporary writable DMG
hdiutil create -srcfolder "$STAGING_DIR" -volname "$VOL_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size 200M "$OUTPUT_DIR/pack.temp.dmg"

# Mount it
DEVICE=$(hdiutil attach -readwrite -noverify "$OUTPUT_DIR/pack.temp.dmg" | egrep '^/dev/' | sed 1q | awk '{print $1}')
sleep 2

# Copy Volume Icon
if [ -f "DarkwareZapret.icns" ]; then
    cp "DarkwareZapret.icns" "/Volumes/$VOL_NAME/.VolumeIcon.icns"
    # Set volume icon attribute (might fail if SetFile not found, ignore error)
    SetFile -a C "/Volumes/$VOL_NAME" 2>/dev/null || true
else
    echo "Warning: DarkwareZapret.icns not found, skipping icon setup."
fi

# Customize with AppleScript
echo "Customizing DMG appearance..."
osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        
        -- Wait for window to actually open
        delay 2
        
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        
        -- Clean window size
        set the bounds of container window to {400, 100, 900, 450}
        
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        
        -- Position icons centered
        set position of item "$APP_NAME" of container window to {120, 170}
        set position of item "Applications" of container window to {380, 170}
        
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# Unmount
hdiutil detach "$DEVICE"

# Convert to final compressed DMG
echo "Compressing final DMG..."
hdiutil convert "$OUTPUT_DIR/pack.temp.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DIR/$DMG_NAME.dmg"

# Cleanup
rm -f "$OUTPUT_DIR/pack.temp.dmg"
rm -rf "$STAGING_DIR"

echo "Done! Installer created at $OUTPUT_DIR/$DMG_NAME.dmg"
