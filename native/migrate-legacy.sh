#!/bin/sh
# Never execute old /opt scripts: earlier releases sourced a world-writable config.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
[ "$(/usr/bin/id -u)" = 0 ] || { echo 'Administrator privileges required.' >&2; exit 1; }
legacy=0
for item in /etc/sudoers.d/darkware-zapret /Library/LaunchDaemons/com.darkware.zapret.plist /opt/darkware-zapret/config_custom; do
    if [ -e "$item" ] || [ -L "$item" ]; then legacy=1; fi
done
[ "$legacy" = 1 ] || exit 0
/bin/rm -f /etc/sudoers.d/darkware-zapret
/bin/launchctl bootout system/com.darkware.zapret >/dev/null 2>&1 || true
/bin/rm -f /Library/LaunchDaemons/com.darkware.zapret.plist
for file in /var/run/tpws1.pid /var/run/tpws2.pid /var/run/tpws3.pid; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    pid=$(/bin/cat "$file")
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    [ "$pid" -gt 1 ] || continue
    command=$(/bin/ps -p "$pid" -o comm= || true)
    if [ "$command" = /opt/darkware-zapret/tpws/tpws ]; then
        /bin/kill -TERM "$pid" 2>/dev/null || true
        /bin/rm -f "$file"
    fi
done
# Older app versions could leave an unleased SOCKS child after the GUI quit.
# Names select candidates only; exact executable paths authorize each signal.
for name in tpws ciadpi; do
    for pid in $(/usr/bin/pgrep -x "$name" 2>/dev/null || true); do
        case "$pid" in ''|*[!0-9]*) continue ;; esac
        [ "$pid" -gt 1 ] || continue
        command=$(/bin/ps -p "$pid" -o comm= || true)
        case "$command" in
            /opt/darkware-zapret/tpws/tpws|/opt/darkware-zapret/byedpi/ciadpi)
                /bin/kill -TERM "$pid" 2>/dev/null || true ;;
        esac
    done
done
for anchor in zapret zapret-v4 zapret-v6; do /sbin/pfctl -a "$anchor" -F all >/dev/null 2>&1 || true; done
# Retire the migration marker without reading or sourcing its contents.
if [ -f /opt/darkware-zapret/config_custom ] && [ ! -L /opt/darkware-zapret/config_custom ]; then
    /bin/rm -f /opt/darkware-zapret/config_custom
fi
printf '%s\n' 'Legacy privilege rule and service retired. DNS and global PF settings were left unchanged.'
