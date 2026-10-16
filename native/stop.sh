#!/bin/sh
set -eu
. '/Library/Application Support/DarkwareZapret/common.sh'
require_root
trusted_path "$BASE"; trusted_path "$RUN"
if [ "${1:-}" != --locked ]; then lock_control; trap unlock_control EXIT; fi
# Remove interception first. bootout sends TERM to the supervisor, whose trap
# also releases our PF reference. Other applications' references remain intact.
clear_intercept
/bin/rm -f "$RUN/ready"
/bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
stop_owned_engine
i=0
while [ -f "$RUN/engine.pid" ]; do
    pid=$(/bin/cat "$RUN/engine.pid")
    engine_is_ours "$pid" || break
    i=$((i + 1))
    if [ "$i" -gt 30 ]; then
        if engine_is_ours "$pid"; then /bin/kill -KILL "$pid" 2>/dev/null || true; fi
        break
    fi
    /bin/sleep 0.1
done
if [ -f "$RUN/watchdog.pid" ] && [ ! -L "$RUN/watchdog.pid" ]; then
    watcher=$(/bin/cat "$RUN/watchdog.pid")
    i=0
    while watchdog_is_ours "$watcher"; do
        i=$((i + 1))
        if [ "$i" -gt 30 ]; then
            if watchdog_is_ours "$watcher"; then /bin/kill -TERM "$watcher" 2>/dev/null || true; fi
            break
        fi
        /bin/sleep 0.1
    done
fi
release_pf_token
/bin/rm -f "$RUN/engine.pid" "$RUN/supervisor.pid" "$RUN/watchdog.pid" "$RUN/engine.conf" "$RUN/engine-check.conf"
/bin/rm -f "$PLIST"
printf '%s\n' 'Darkware packet mode stopped.'
