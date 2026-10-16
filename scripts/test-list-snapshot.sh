#!/bin/bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
mkdir -p "$ROOT/.build"
HELPER=${1:-"$ROOT/.build/engines/snapshot-list"}
STAGE=$(mktemp -d "$ROOT/.build/snapshot-check.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
UID_EXPECTED=$(id -u)
printf 'example.com\n' > "$STAGE/source.txt"
"$HELPER" "$STAGE/source.txt" "$STAGE/copy.txt" "$UID_EXPECTED"
cmp "$STAGE/source.txt" "$STAGE/copy.txt"
reject() {
    if "$HELPER" "$1" "$STAGE/rejected.txt" "$2" >/dev/null 2>&1; then echo "Unsafe source accepted: $1" >&2; exit 1; fi
    [ ! -e "$STAGE/rejected.txt" ] || { echo 'Failed copy left a destination.' >&2; exit 1; }
}
ln -s "$STAGE/source.txt" "$STAGE/symlink.txt"
reject "$STAGE/symlink.txt" "$UID_EXPECTED"
ln -s "$STAGE" "$STAGE/linked-directory"
reject "$STAGE/linked-directory/source.txt" "$UID_EXPECTED"
reject "$STAGE/source.txt" "$((UID_EXPECTED + 1))"
reject "$STAGE" "$UID_EXPECTED"
mkfifo "$STAGE/fifo"
reject "$STAGE/fifo" "$UID_EXPECTED"
dd if=/dev/zero of="$STAGE/oversized.txt" bs=1 count=1 seek=16777216 2>/dev/null
reject "$STAGE/oversized.txt" "$UID_EXPECTED"
if "$HELPER" "$STAGE/source.txt" "$STAGE/copy.txt" "$UID_EXPECTED" >/dev/null 2>&1; then echo 'Existing destination was overwritten.' >&2; exit 1; fi
printf '%s\n' 'List snapshot checks passed: byte equality, symlink file and ancestor, owner, directory, FIFO, size and overwrite rejection.'
