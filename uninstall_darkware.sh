#!/bin/sh
# Run explicitly with administrator privileges. User preferences remain available.
set -eu
[ "$(/usr/bin/id -u)" = 0 ] || { echo 'Run with sudo to remove the privileged packet service.' >&2; exit 1; }
HERE=$(CDPATH= cd -- "$(/usr/bin/dirname -- "$0")" && pwd -P)
BASE='/Library/Application Support/DarkwareZapret'
if [ -d "$BASE" ]; then
    [ ! -L "$BASE" ] && [ "$(/usr/bin/stat -f '%u' "$BASE")" = 0 ] || { echo 'Refusing untrusted service directory.' >&2; exit 1; }
    exec_mode=$(/usr/bin/stat -f '%OLp' "$BASE")
    [ $((0$exec_mode & 0022)) = 0 ] || exit 1
    for file in common.sh stop.sh; do
        [ -f "$BASE/$file" ] && [ ! -L "$BASE/$file" ] && [ "$(/usr/bin/stat -f '%u' "$BASE/$file")" = 0 ] || exit 1
        exec_mode=$(/usr/bin/stat -f '%OLp' "$BASE/$file")
        [ $((0$exec_mode & 0022)) = 0 ] || exit 1
    done
    /bin/sh "$BASE/stop.sh"
    /bin/rm -rf "$BASE"
fi
if [ -f "$HERE/native/migrate-legacy.sh" ]; then /bin/sh "$HERE/native/migrate-legacy.sh"; fi
/bin/rm -f /Library/LaunchDaemons/com.darkware.zapret.packet.plist
/bin/rmdir /var/run/com.darkware.zapret.packet 2>/dev/null || true
printf '%s\n' 'Privileged Darkware services removed. Remove the app from Applications separately.'
