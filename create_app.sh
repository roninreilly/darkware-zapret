#!/bin/bash
# Builds a universal app, compressed DMG, ZIP, matching source and provenance offline.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
cd "$ROOT"
VERSION=${1:-$(cat "$ROOT/VERSION")}
VERSION=${VERSION#v}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]] || { echo 'Invalid semantic version.' >&2; exit 1; }
CORE_VERSION=${VERSION%%-*}
BUNDLE_VERSION=$CORE_VERSION
if [[ "$VERSION" == *-* ]]; then BUNDLE_VERSION="${CORE_VERSION}b${VERSION##*.}"; fi
DIST="$ROOT/dist"
APP="$DIST/darkware zapret.app"
STEM="DarkwareZapret_v${VERSION}"
mkdir -p "$DIST" "$ROOT/.build"
./scripts/test-native.sh
./scripts/build-engines.sh
./scripts/check-runtime-engines.sh
./scripts/check-engine-presets.sh
/usr/bin/python3 ./scripts/test-native-lifecycle.py
/usr/bin/python3 ./scripts/smoke-socks.py "$ROOT/.build/engines"
# A multi-architecture SwiftPM build requires Xcode's xcbuild. Separate triples
# also work with Command Line Tools and keep the deployment target at macOS 13.
SWIFT_BINARIES=()
for ARCH in arm64 x86_64; do
    SCRATCH="$ROOT/.build/app-$ARCH"
    TRIPLE="$ARCH-apple-macosx13.0"
    swift build --scratch-path "$SCRATCH" -c release --triple "$TRIPLE" -Xswiftc -parse-as-library
    BIN=$(swift build --scratch-path "$SCRATCH" -c release --triple "$TRIPLE" --show-bin-path)
    [ -f "$BIN/DarkwareZapret" ] || { echo "Swift executable missing for $ARCH." >&2; exit 1; }
    SWIFT_BINARIES+=("$BIN/DarkwareZapret")
done
UNIVERSAL="$ROOT/.build/DarkwareZapret-universal"
xcrun lipo -create "${SWIFT_BINARIES[@]}" -output "$UNIVERSAL"
xcrun lipo "$UNIVERSAL" -verify_arch arm64 x86_64
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Engines" "$APP/Contents/Resources/Licenses"
cp "$UNIVERSAL" "$APP/Contents/MacOS/DarkwareZapret"
cp -R "$ROOT/native" "$APP/Contents/Resources/Native"
cp "$ROOT/.build/engines/snapshot-list" "$APP/Contents/Resources/Native/snapshot-list"
cp "$ROOT/.build/engines/"{utunws,tpws,ciadpi} "$APP/Contents/Resources/Engines/"
cp "$ROOT/DarkwareZapret.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/DarkwareZapret.txt"
cp "$ROOT/vendor/flowseal/LICENSE" "$APP/Contents/Resources/Licenses/Flowseal.txt"
cp "$ROOT/vendor/zapret/LICENSE.txt" "$APP/Contents/Resources/Licenses/zapret.txt"
cp "$ROOT/vendor/byedpi/LICENSE" "$APP/Contents/Resources/Licenses/ByeDPI.txt"
cp "$ROOT/vendor/zapret/tpws/andr/_musl_license.txt" "$APP/Contents/Resources/Licenses/musl.txt"
cp "$ROOT/vendor/zapret/tpws/epoll-shim/LICENSE" "$APP/Contents/Resources/Licenses/epoll-shim.txt"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>darkware zapret</string>
<key>CFBundleDisplayName</key><string>darkware zapret</string>
<key>CFBundleIdentifier</key><string>com.darkware.zapret</string>
<key>CFBundleExecutable</key><string>DarkwareZapret</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$CORE_VERSION</string>
<key>CFBundleVersion</key><string>$BUNDLE_VERSION</string>
<key>DarkwareReleaseVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
xcrun lipo "$APP/Contents/MacOS/DarkwareZapret" -verify_arch arm64 x86_64
/usr/bin/python3 "$ROOT/scripts/write-provenance.py" "$APP" "$VERSION" "$APP/Contents/Resources/build-provenance.json"
# Engines/helpers were signed first. Seal the outer app without resigning them.
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/python3 "$ROOT/scripts/write-provenance.py" "$APP" "$VERSION" "$DIST/$STEM.provenance.json" --sealed
# Headless packaging does not launch Finder, mount a volume or change host state.
STAGE=$(mktemp -d "$ROOT/.build/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/${STEM}_Installer.dmg" "$DIST/${STEM}.zip" "$DIST/${STEM}_Source.tar.gz"
hdiutil create -srcfolder "$STAGE" -volname 'Darkware Zapret' -format UDZO -imagekey zlib-level=9 "$DIST/${STEM}_Installer.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/${STEM}.zip"
SOURCE_FILES=(Sources vendor native scripts Package.swift VERSION create_app.sh install_darkware.sh uninstall_darkware.sh LICENSE DarkwareZapret.icns)
for ITEM in Tests docs README.md README.ru.md; do [ ! -e "$ITEM" ] || SOURCE_FILES+=("$ITEM"); done
tar -czf "$DIST/${STEM}_Source.tar.gz" "${SOURCE_FILES[@]}"
(
    cd "$DIST"
    shasum -a 256 "${STEM}_Installer.dmg" "${STEM}.zip" "${STEM}_Source.tar.gz" "${STEM}.provenance.json" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)
printf '%s\n' "Release artifacts ready in $DIST"
