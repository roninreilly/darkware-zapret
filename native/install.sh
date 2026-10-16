#!/bin/sh
set -eu
umask 022
SOURCE=$(CDPATH= cd -- "$(/usr/bin/dirname -- "$0")" && pwd -P)
. "$SOURCE/common.sh"
if [ "${1:-}" = --check ]; then
    [ "$#" = 4 ] || fail 'Usage: install.sh --check dataRoot strategyId ipsetMode'
    validate_data_root "$2"; validate_selection "$3" "$4"
    printf '%s\n' 'Native selection validated.'
    exit 0
fi
[ "$#" = 3 ] || fail 'Usage: install.sh dataRoot strategyId ipsetMode'
validate_data_root "$1"; validate_selection "$2" "$3"
DATA_ROOT=$1; STRATEGY=$2; IPSET=$3
require_root
major=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)
[ "$major" -ge 14 ] || fail 'Packet mode requires macOS 14 or newer.'
trusted_path '/Library/Application Support'
trusted_path "$BASE"
trusted_path "$PLIST"
trusted_path "$RUN"
if [ -d "$RUN" ]; then
    for name in engine.pid supervisor.pid watchdog.pid engine.conf engine-check.conf ready pf-token service.plist; do trusted_path "$RUN/$name"; done
fi
lock_control
STAGE=
STARTED=0
SUCCEEDED=0
cleanup_install() {
    if [ "$STARTED" = 1 ] && [ "$SUCCEEDED" = 0 ]; then /bin/sh "$BASE/stop.sh" --locked >/dev/null 2>&1 || true; fi
    [ -z "$STAGE" ] || /bin/rm -rf "$STAGE"
    unlock_control
}
trap cleanup_install EXIT
trap 'exit 1' HUP INT TERM
# Stop only a previously secured Darkware v2 service.
if [ -d "$BASE" ]; then
    trusted_path "$BASE/common.sh"; trusted_path "$BASE/stop.sh"
    /bin/sh "$BASE/stop.sh" --locked
fi
if /sbin/ifconfig utun50 >/dev/null 2>&1; then fail 'utun50 is occupied. Stop the conflicting app before starting packet mode.'; fi
if vpn_routes_present; then fail 'An IPv4 VPN/tunnel route is active. Stop the VPN before using packet mode.'; fi
# Fresh root-owned staging means user data never becomes executable service configuration.
STAGE=$(/usr/bin/mktemp -d '/Library/Application Support/.DarkwareZapret.XXXXXX')
/bin/mkdir "$STAGE/bin" "$STAGE/lists" "$STAGE/strategies"
for name in common.sh run.sh stop.sh watchdog.sh migrate-legacy.sh strategies.tsv ipset-none.txt ipset-any.txt; do
    [ -f "$SOURCE/$name" ] && [ ! -L "$SOURCE/$name" ] || fail "Invalid payload: $name"
    /usr/bin/install -m 644 "$SOURCE/$name" "$STAGE/$name"
done
for file in "$SOURCE"/strategies/*.conf.in "$SOURCE"/bin/*.bin; do
    [ -f "$file" ] && [ ! -L "$file" ] || fail 'Invalid packet data payload.'
    case "$file" in *.conf.in) dest="$STAGE/strategies" ;; *) dest="$STAGE/bin" ;; esac
    /usr/bin/install -m 644 "$file" "$dest/$(/usr/bin/basename "$file")"
done
ENGINE="$SOURCE/../Engines/utunws"
[ -f "$ENGINE" ] && [ ! -L "$ENGINE" ] || fail 'Bundled packet engine is missing.'
/usr/bin/install -m 755 "$ENGINE" "$STAGE/bin/utunws"
SNAPSHOT="$SOURCE/snapshot-list"
[ -f "$SNAPSHOT" ] && [ ! -L "$SNAPSHOT" ] || fail 'Bundled list snapshot helper is missing.'
/usr/bin/install -m 755 "$SNAPSHOT" "$STAGE/bin/snapshot-list"
DATA_OWNER=$(/usr/bin/stat -f '%u' "$DATA_ROOT")
[ ! -L "$DATA_ROOT/lists" ] || fail 'Refusing symlink list directory.'
for name in list-general.txt list-general-user.txt list-google.txt list-exclude.txt list-exclude-user.txt ipset-all.txt ipset-exclude.txt ipset-exclude-user.txt; do
    file="$SOURCE/default-lists/$name"
    if [ -e "$DATA_ROOT/lists/$name" ] || [ -L "$DATA_ROOT/lists/$name" ]; then
        "$STAGE/bin/snapshot-list" "$DATA_ROOT/lists/$name" "$STAGE/lists/$name" "$DATA_OWNER"
        continue
    fi
    [ -f "$file" ] && [ ! -L "$file" ] || fail "List must be a regular file: $name"
    [ "$(/usr/bin/stat -f '%z' "$file")" -le 16777216 ] || fail 'List exceeds 16 MiB limit.'
    /usr/bin/install -m 644 "$file" "$STAGE/lists/$name"
done
printf '%s\n' "$STRATEGY" > "$STAGE/selected-strategy"
printf '%s\n' "$IPSET" > "$STAGE/ipset-mode"
/usr/sbin/chown -R root:wheel "$STAGE"
/bin/chmod -R go-w "$STAGE"
# Replace only an already validated service directory.
[ ! -d "$BASE" ] || /bin/rm -rf "$BASE"
/bin/mv "$STAGE" "$BASE"
STAGE=
/bin/chmod 755 "$BASE" "$BASE/bin" "$BASE/lists" "$BASE/strategies"
/bin/sh "$BASE/migrate-legacy.sh"
/bin/mkdir -p "$RUN"
/usr/sbin/chown root:wheel "$RUN"
/bin/chmod 755 "$RUN"
/bin/rm -f "$RUN/ready"
# No autostart: start is an explicit administrator-authorized session.
cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.darkware.zapret.packet</string>
<key>ProgramArguments</key><array><string>/bin/sh</string><string>/Library/Application Support/DarkwareZapret/run.sh</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><false/>
<key>AbandonProcessGroup</key><true/>
<key>StandardOutPath</key><string>/Library/Application Support/DarkwareZapret/engine.log</string>
<key>StandardErrorPath</key><string>/Library/Application Support/DarkwareZapret/engine.log</string>
</dict></plist>
PLIST
/usr/sbin/chown root:wheel "$PLIST"
/bin/chmod 644 "$PLIST"
STARTED=1
/bin/launchctl bootstrap system "$PLIST"
i=0
while [ ! -f "$RUN/ready" ]; do
    i=$((i + 1))
    if [ "$i" -gt 100 ]; then
        /bin/sh "$BASE/stop.sh" --locked
        /usr/bin/tail -30 "$BASE/engine.log" >&2 || true
        fail 'Packet service failed to become ready; interception was cleared.'
    fi
    /bin/sleep 0.1
done
SUCCEEDED=1
printf '%s\n' 'Experimental IPv4 packet mode started.'
