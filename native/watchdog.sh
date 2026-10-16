#!/bin/sh
set -eu
. '/Library/Application Support/DarkwareZapret/common.sh'
require_root
SUPERVISOR=$1
ENGINE=$2
case "$SUPERVISOR:$ENGINE" in *[!0-9:]*) exit 1 ;; esac
# launchd leaves this process alive when its supervised shell dies unexpectedly.
# Clear PF before killing the engine, including when the shell was SIGKILLed.
while kill -0 "$SUPERVISOR" 2>/dev/null && engine_is_ours "$ENGINE"; do /bin/sleep 0.2; done
clear_intercept
/bin/rm -f "$RUN/ready"
if engine_is_ours "$ENGINE"; then /bin/kill -TERM "$ENGINE" 2>/dev/null || true; fi
release_pf_token
/bin/rm -f "$RUN/engine.pid" "$RUN/supervisor.pid"
