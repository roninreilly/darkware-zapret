#!/bin/sh
set -eu
umask 022
. '/Library/Application Support/DarkwareZapret/common.sh'
require_root
trusted_path "$BASE"; trusted_path "$RUN"
ENGINE_PID=
WATCHDOG_PID=
cleanup() {
    trap - EXIT INT TERM HUP
    clear_intercept
    /bin/rm -f "$RUN/ready"
    if [ -n "$ENGINE_PID" ] && engine_is_ours "$ENGINE_PID"; then /bin/kill -TERM "$ENGINE_PID" 2>/dev/null || true; fi
    if [ -n "$ENGINE_PID" ]; then wait "$ENGINE_PID" 2>/dev/null || true; fi
    release_pf_token
    if [ -n "$WATCHDOG_PID" ]; then /bin/kill -TERM "$WATCHDOG_PID" 2>/dev/null || true; fi
    if [ -n "$WATCHDOG_PID" ]; then wait "$WATCHDOG_PID" 2>/dev/null || true; fi
    /bin/rm -f "$RUN/engine.pid" "$RUN/supervisor.pid" "$RUN/watchdog.pid"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
/bin/rm -f "$RUN/ready" "$RUN/engine.pid"
printf '%s\n' "$$" > "$RUN/supervisor.pid"
if /sbin/ifconfig utun50 >/dev/null 2>&1; then fail 'utun50 is already occupied.'; fi
if vpn_routes_present; then fail 'IPv4 VPN routes are active.'; fi
# Loading a child anchor requires the standard Apple wildcard in the active PF ruleset.
/sbin/pfctl -sr 2>/dev/null | /usr/bin/grep -F 'anchor "com.apple/*"' >/dev/null || fail 'The active PF ruleset does not contain the standard com.apple/* anchor. No PF configuration was changed.'
PHYSICAL_IFACE=$(/sbin/route -n get default | /usr/bin/awk '/interface:/{print $2; exit}')
GATEWAY=$(/sbin/route -n get default | /usr/bin/awk '/gateway:/{print $2; exit}')
case "$PHYSICAL_IFACE" in en[0-9]*) ;; *) fail 'A physical Ethernet/Wi-Fi IPv4 default route is required.' ;; esac
case "$GATEWAY" in ''|*[!0-9.]*) fail 'An IPv4 gateway is required.' ;; esac
/sbin/ping -c 1 -t 1 "$GATEWAY" >/dev/null 2>&1 || true
GATEWAY_MAC=$(/usr/sbin/arp -n "$GATEWAY" | /usr/bin/awk '/ at /{print $4; exit}')
printf '%s\n' "$GATEWAY_MAC" | /usr/bin/grep -Eq '^([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}$' || fail 'Cannot resolve the IPv4 gateway MAC address.'
STRATEGY=$(/bin/cat "$BASE/selected-strategy")
IPSET_MODE=$(/bin/cat "$BASE/ipset-mode")
validate_selection "$STRATEGY" "$IPSET_MODE"
case "$IPSET_MODE" in loaded) IPSET="$BASE/lists/ipset-all.txt" ;; any) IPSET="$BASE/ipset-any.txt" ;; none) IPSET="$BASE/ipset-none.txt" ;; esac
/usr/bin/sed -e "s|@BASE@|$BASE|g" -e "s|@LISTS@|$BASE/lists|g" -e "s|@IPSET@|$IPSET|g" "$BASE/strategies/$STRATEGY.conf.in" > "$RUN/engine.conf"
printf '\n--uid=1:1\n' >> "$RUN/engine.conf"
# Parse every selected argument before opening utun or changing packet filtering.
/bin/cp "$RUN/engine.conf" "$RUN/engine-check.conf"
printf '\n--dry-run\n' >> "$RUN/engine-check.conf"
"$BASE/bin/utunws" @"$RUN/engine-check.conf"
export ZAPRET_IFACE="$PHYSICAL_IFACE" ZAPRET_GATEWAY_MAC="$GATEWAY_MAC" ZAPRET_GATEWAY6_MAC='' ZAPRET_UTUN_UNIT=51
"$BASE/bin/utunws" @"$RUN/engine.conf" &
ENGINE_PID=$!
printf '%s\n' "$ENGINE_PID" > "$RUN/engine.pid"
i=0
while ! /sbin/ifconfig utun50 >/dev/null 2>&1; do
    i=$((i + 1))
    if ! kill -0 "$ENGINE_PID" 2>/dev/null || [ "$i" -gt 100 ]; then fail 'Packet engine did not create utun50.'; fi
    /bin/sleep 0.1
done
/sbin/ifconfig utun50 10.77.0.1 10.77.0.2 netmask 255.255.255.255 up
/bin/sh "$BASE/watchdog.sh" "$$" "$ENGINE_PID" &
WATCHDOG_PID=$!
printf '%s\n' "$WATCHDOG_PID" > "$RUN/watchdog.pid"
# Hold our own PF reference even when another app has already enabled PF.
PF_OUTPUT=$(/sbin/pfctl -E 2>&1) || fail 'Cannot obtain a PF enable reference.'
TOKEN=$(printf '%s\n' "$PF_OUTPUT" | /usr/bin/awk '/Token :/ {print $3; exit}')
case "$TOKEN" in ''|*[!0-9]*) fail 'PF did not return an enable token.' ;; esac
printf '%s\n' "$TOKEN" > "$RUN/pf-token"
printf '%s\n' \
 'pass out quick route-to (utun50 10.77.0.2) inet proto tcp from any to any port {80,443,2053,2083,2087,2096,8443} user { >root } no state' \
 'pass out quick route-to (utun50 10.77.0.2) inet proto udp from any to any port {443,19294:19344,50000:50100} user { >root } no state' \
 | /sbin/pfctl -a "$ANCHOR" -f -
printf '%s\n' "$ENGINE_PID" > "$RUN/ready"
while kill -0 "$ENGINE_PID" 2>/dev/null; do
    /bin/sleep 1
    current_iface=$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')
    current_gateway=$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/gateway:/{print $2; exit}')
    [ "$current_iface" = "$PHYSICAL_IFACE" ] && [ "$current_gateway" = "$GATEWAY" ] || fail 'Default network route changed; packet mode stopped.'
    if vpn_routes_present; then fail 'An IPv4 VPN route appeared; packet mode stopped.'; fi
done
fail 'Packet engine exited; interception was cleared.'
