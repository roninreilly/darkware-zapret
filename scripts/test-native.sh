#!/bin/bash
# No sudo, PF, routes, launchd, DNS or host state changes. Tests run unprivileged.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
mkdir -p "$ROOT/.build"
for script in "$ROOT"/native/*.sh "$ROOT"/install_darkware.sh "$ROOT"/uninstall_darkware.sh; do /bin/sh -n "$script"; done
for script in "$ROOT"/scripts/*.sh "$ROOT/create_app.sh"; do /bin/bash -n "$script"; done
TESTDIR=$(mktemp -d "$ROOT/.build/native-check.XXXXXX")
trap 'rm -rf "$TESTDIR"' EXIT
while IFS=$'\t' read -r STRATEGY TITLE; do
    [ -f "$ROOT/native/strategies/$STRATEGY.conf.in" ]
    for MODE in none loaded any; do /bin/sh "$ROOT/native/install.sh" --check "$TESTDIR" "$STRATEGY" "$MODE" >/dev/null; done
done < "$ROOT/native/strategies.tsv"
for BAD in '../general' 'general;touch bad' 'general-alt13' ''; do
    if /bin/sh "$ROOT/native/install.sh" --check "$TESTDIR" "$BAD" none 2>/dev/null; then echo 'Invalid strategy was accepted.' >&2; exit 1; fi
done
if /bin/sh "$ROOT/native/install.sh" --check "$TESTDIR" general 'any;id' 2>/dev/null; then exit 1; fi
ln -s "$TESTDIR" "$TESTDIR/link"
if /bin/sh "$ROOT/native/install.sh" --check "$TESTDIR/link" general none 2>/dev/null; then echo 'Symlink directory was accepted.' >&2; exit 1; fi
if /bin/sh "$ROOT/native/install.sh" --check "$TESTDIR/link/.." general none 2>/dev/null; then exit 1; fi
if rg -n 'killall|pkill|NOPASSWD|chmod 666|pfctl -d|networksetup|eval ' "$ROOT/native" "$ROOT/install_darkware.sh"; then echo 'Forbidden privileged primitive found.' >&2; exit 1; fi
printf '%s\n' 'Native script syntax and 63 valid selections, invalid input and symlink checks passed.'
