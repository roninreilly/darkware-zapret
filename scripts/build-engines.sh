#!/bin/bash
# Offline build: every engine and packet fixture is pinned in vendor/ and native/.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
OUT=${1:-"$ROOT/.build/engines"}
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CLANG=$(xcrun --find clang)
mkdir -p "$OUT" "$ROOT/.build"
SCRATCH=$(mktemp -d "$ROOT/.build/engine-build.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
for ARCH in arm64 x86_64; do
    COMMON=(-isysroot "$SDKROOT" -target "$ARCH-apple-macos13.0" -Os -std=gnu99 -Wno-address-of-packed-member)
    "$CLANG" -isysroot "$SDKROOT" -target "$ARCH-apple-macos14.0" -Os -std=gnu99 -Wno-address-of-packed-member \
        "$ROOT"/vendor/flowseal/nfq/*.c "$ROOT"/vendor/flowseal/nfq/crypto/*.c \
        -lz -Wl,-dead_strip -o "$SCRATCH/utunws-$ARCH"
    "$CLANG" "${COMMON[@]}" -I"$ROOT/vendor/zapret/tpws/epoll-shim/include" -I"$ROOT/vendor/zapret/tpws/macos" \
        "$ROOT"/vendor/zapret/tpws/*.c "$ROOT"/vendor/zapret/tpws/epoll-shim/src/*.c \
        -lz -lpthread -Wl,-dead_strip -o "$SCRATCH/tpws-$ARCH"
    "$CLANG" "${COMMON[@]}" -D_DEFAULT_SOURCE -I"$ROOT/vendor/byedpi" \
        "$ROOT"/vendor/byedpi/{packets,main,conev,proxy,desync,mpool,extend}.c \
        -Wl,-dead_strip -o "$SCRATCH/ciadpi-$ARCH"
    "$CLANG" "${COMMON[@]}" -Wall -Wextra -Werror "$ROOT/native/snapshot-list.c" -o "$SCRATCH/snapshot-list-$ARCH"
done
for ENGINE in utunws tpws ciadpi snapshot-list; do
    xcrun lipo -create "$SCRATCH/$ENGINE-arm64" "$SCRATCH/$ENGINE-x86_64" -output "$OUT/$ENGINE"
    xcrun strip "$OUT/$ENGINE"
    codesign --force --sign - "$OUT/$ENGINE"
    xcrun lipo "$OUT/$ENGINE" -verify_arch arm64 x86_64
    codesign --verify --strict "$OUT/$ENGINE"
done
printf '%s\n' "Universal engines built from vendored sources in $OUT"
