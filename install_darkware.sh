#!/bin/sh
# Compatibility entry point for administrators. The app calls Native/install.sh.
set -eu
HERE=$(CDPATH= cd -- "$(/usr/bin/dirname -- "$0")" && pwd -P)
if [ -f "$HERE/Native/install.sh" ]; then
    exec /bin/sh "$HERE/Native/install.sh" "$@"
fi
printf '%s\n' 'Build the v2 app first, then start packet mode from its menu. This legacy installer no longer creates passwordless sudo rules.' >&2
exit 1
