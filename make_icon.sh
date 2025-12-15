#!/bin/bash
ICON="app_icon.png"
ICONSET="DarkwareZapret.iconset"

mkdir -p "$ICONSET"

# Function to resize
resize() {
    SIZE=$1
    NAME=$2
    sips -z $SIZE $SIZE "$ICON" --out "$ICONSET/$NAME"
}

resize 16 "icon_16x16.png"
resize 32 "icon_16x16@2x.png"
resize 32 "icon_32x32.png"
resize 64 "icon_32x32@2x.png"
resize 128 "icon_128x128.png"
resize 256 "icon_128x128@2x.png"
resize 256 "icon_256x256.png"
resize 512 "icon_256x256@2x.png"
resize 512 "icon_512x512.png"
resize 1024 "icon_512x512@2x.png"

echo "Creating icns..."
iconutil -c icns "$ICONSET"
rm -rf "$ICONSET"
echo "Done. Created DarkwareZapret.icns"
