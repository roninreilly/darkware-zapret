#!/bin/bash
# Parse every shipped Flowseal preset without opening utun or requiring root.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
mkdir -p "$ROOT/.build"
ENGINE_DIR=${1:-"$ROOT/.build/engines"}
STAGE=$(mktemp -d "$ROOT/.build/preset-check.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/native/bin" "$ROOT/native/default-lists" "$STAGE/"
for MODE in none any loaded; do
    case "$MODE" in none) IPSET="$ROOT/native/ipset-none.txt" ;; any) IPSET="$ROOT/native/ipset-any.txt" ;; loaded) IPSET="$STAGE/default-lists/ipset-all.txt" ;; esac
    while IFS=$'\t' read -r ID TITLE; do
        sed -e "s|@BASE@|$STAGE|g" -e "s|@LISTS@|$STAGE/default-lists|g" -e "s|@IPSET@|$IPSET|g" "$ROOT/native/strategies/$ID.conf.in" > "$STAGE/preset.conf"
        printf '\n--dry-run\n' >> "$STAGE/preset.conf"
        "$ENGINE_DIR/utunws" @"$STAGE/preset.conf" > "$STAGE/result" 2>&1 || { cat "$STAGE/result"; echo "Failed preset: $ID / $MODE" >&2; exit 1; }
    done < "$ROOT/native/strategies.tsv"
done
"$ENGINE_DIR/tpws" --socks --bind-addr=127.0.0.1 --port=1080 --split-pos=1,midsld --disorder --dry-run
"$ENGINE_DIR/ciadpi" --version
"$ROOT/scripts/test-list-snapshot.sh" "$ENGINE_DIR/snapshot-list"
printf '%s\n' 'All 63 packet preset configurations and proxy engine smoke checks passed.'
