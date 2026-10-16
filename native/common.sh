#!/bin/sh
# Constants and validation only. No user-controlled shell configuration is loaded.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
BASE='/Library/Application Support/DarkwareZapret'
RUN=/var/run/com.darkware.zapret.packet
LABEL=com.darkware.zapret.packet
PLIST=$RUN/service.plist
ANCHOR=com.apple/darkware-zapret
CONTROL=/var/run/com.darkware.zapret.packet.control
fail() { printf '%s\n' "$*" >&2; exit 1; }
require_root() { [ "$(/usr/bin/id -u)" = 0 ] || fail 'Administrator privileges required.'; }
validate_selection() {
    case "$1" in general|general-alt|general-alt[2-9]|general-alt1[0-2]|general-exp|general-fake-tls-auto|general-fake-tls-auto-alt|general-fake-tls-auto-alt2|general-fake-tls-auto-alt3|general-simple-fake|general-simple-fake-alt|general-simple-fake-alt2) ;; *) fail 'Unknown packet strategy.' ;; esac
    case "$2" in none|loaded|any) ;; *) fail 'Unknown IPSet mode.' ;; esac
}
validate_data_root() {
    case "$1" in /*) ;; *) fail 'Data directory must be absolute.' ;; esac
    case "$1" in *'/../'*|*/..|*'/./'*|*/.|*'//'*) fail 'Non-canonical data directory.' ;; esac
    [ -d "$1" ] && [ ! -L "$1" ] || fail 'Data directory is missing or is a symlink.'
    p=$1
    while [ "$p" != / ]; do
        [ ! -L "$p" ] || fail 'Symlink in data directory path.'
        p=${p%/*}; [ -n "$p" ] || p=/
    done
}
# Existing privileged paths must belong to root and must not be writable by other users.
trusted_path() {
    [ ! -L "$1" ] || fail "Refusing symlink: $1"
    [ -e "$1" ] || return 0
    [ "$(/usr/bin/stat -f '%u' "$1")" = 0 ] || fail "Untrusted owner: $1"
    mode=$(/usr/bin/stat -f '%OLp' "$1")
    [ $((0$mode & 0022)) = 0 ] || fail "Untrusted permissions: $1"
}
lock_control() {
    /bin/mkdir -m 700 "$CONTROL" 2>/dev/null || fail 'Another packet operation is running. If a previous operation was interrupted, remove the root-owned control directory after checking no operation is active.'
}
unlock_control() { /bin/rmdir "$CONTROL" 2>/dev/null || true; }
engine_is_ours() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -gt 1 ] || return 1
    owner=$(/bin/ps -p "$1" -o uid= | /usr/bin/tr -d ' ')
    case "$owner" in 0|1) ;; *) return 1 ;; esac
    [ "$(/bin/ps -p "$1" -o comm=)" = "$BASE/bin/utunws" ]
}
watchdog_is_ours() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -gt 1 ] || return 1
    [ "$(/bin/ps -p "$1" -o uid= | /usr/bin/tr -d ' ')" = 0 ] || return 1
    command=$(/bin/ps -p "$1" -o command= || true)
    case "$command" in "/bin/sh $BASE/watchdog.sh "*) return 0 ;; *) return 1 ;; esac
}
clear_intercept() { /sbin/pfctl -a "$ANCHOR" -F all >/dev/null 2>&1 || true; }
release_pf_token() {
    if [ -f "$RUN/pf-token" ] && [ ! -L "$RUN/pf-token" ]; then
        token=$(/bin/cat "$RUN/pf-token")
        /bin/rm -f "$RUN/pf-token"
        case "$token" in ''|*[!0-9]*) ;; *) /sbin/pfctl -X "$token" >/dev/null 2>&1 || true ;; esac
    fi
}
stop_owned_engine() {
    if [ -f "$RUN/engine.pid" ] && [ ! -L "$RUN/engine.pid" ]; then
        pid=$(/bin/cat "$RUN/engine.pid")
        if engine_is_ours "$pid"; then /bin/kill -TERM "$pid" 2>/dev/null || true; fi
    fi
}
vpn_routes_present() {
    /usr/sbin/netstat -rn -f inet | /usr/bin/awk '{for (i=1; i<=NF; i++) if ($i ~ /^(utun|tun|ppp|ipsec)[0-9]/ && $i != "utun50") found=1} END {exit !found}'
}
