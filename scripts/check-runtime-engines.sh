#!/bin/sh
# Exercise the actual Swift process runtime inside a temporary bundle; no admin or proxy settings.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
TEST_ROOT=$(mktemp -d "$PWD/.build/runtime-integration.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
APP="$TEST_ROOT/RuntimeChecks.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Engines"
for ENGINE in tpws ciadpi; do
    test -x ".build/engines/$ENGINE" || { printf 'Build engines first: ./scripts/build-engines.sh\n' >&2; exit 1; }
    cp ".build/engines/$ENGINE" "$APP/Contents/Resources/Engines/$ENGINE"
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.darkware.zapret.runtime-checks</string>
<key>CFBundleExecutable</key><string>RuntimeChecks</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
/usr/bin/xcrun swiftc -swift-version 6 -parse-as-library \
    Sources/Models.swift Sources/ProxySettings.swift Sources/Runtime.swift Sources/Diagnostics.swift \
    Tests/StandaloneRuntimeChecks.swift -o "$APP/Contents/MacOS/RuntimeChecks"
"$APP/Contents/MacOS/RuntimeChecks" --bundled-engines
