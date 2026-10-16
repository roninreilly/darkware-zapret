#!/bin/sh
# Standalone regression checks for installations with Command Line Tools but no XCTest/Testing SDK.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
/usr/bin/xcrun swiftc -swift-version 6 -parse-as-library \
    Sources/Models.swift Sources/ProxySettings.swift Sources/Runtime.swift Sources/Diagnostics.swift \
    Tests/StandaloneRuntimeChecks.swift -o .build/runtime-checks
exec .build/runtime-checks
