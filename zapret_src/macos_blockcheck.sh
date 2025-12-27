#!/bin/bash
#
# Darkware Zapret - macOS Diagnostics (Full Version)
# Uses brute-force to test multiple bypass strategies for both tpws and ciadpi.
#

# Configuration
ZAPRET_BASE="${ZAPRET_BASE:-/opt/darkware-zapret}"
TPWS="${ZAPRET_BASE}/tpws/tpws"
CIADPI="${ZAPRET_BASE}/byedpi/ciadpi"
CURL_TIMEOUT="${CURL_TIMEOUT:-2}"
SOCKS_PORT="${SOCKS_PORT:-19999}"
DOMAIN="${DOMAIN:-discord.com}"
TEST_URL="https://${DOMAIN}"
HTTP_URL="http://${DOMAIN}"

# Global State
declare -a WORKING_STRATEGIES
ENGINE_PID=""

# Cleanup Function
cleanup() {
    if [ -n "$ENGINE_PID" ]; then
        kill -9 "$ENGINE_PID" 2>/dev/null || true
        wait "$ENGINE_PID" 2>/dev/null || true
        ENGINE_PID=""
    fi
}
trap cleanup EXIT INT TERM

# --- CHECKS ---

check_system() {
    echo "=== SYSTEM INFO ==="
    echo "macOS: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
    echo "Arch: $(uname -m)"
    echo "curl: $(curl --version 2>/dev/null | head -1 | cut -d' ' -f1-2)"
    
    if [ ! -x "$TPWS" ]; then
        echo "tpws: NOT FOUND at $TPWS"
        exit 1
    fi
    echo "tpws: OK"
    
    if [ ! -x "$CIADPI" ]; then
        echo "ciadpi: NOT FOUND at $CIADPI"
    else
        echo "ciadpi: OK"
    fi
    
    # Find free port
    for p in $(seq 19999 20050); do
        if ! nc -z -w 1 127.0.0.1 $p 2>/dev/null; then
            SOCKS_PORT=$p
            break
        fi
    done
    echo "Using SOCKS Port: $SOCKS_PORT"
    echo ""
}

check_dns() {
    echo "=== DNS CHECK ==="
    local ips=$(dig +short "$DOMAIN" A 2>/dev/null | head -3)
    if [ -z "$ips" ]; then
        echo "DNS: FAILED - cannot resolve $DOMAIN"
        # Try 8.8.8.8
        ips=$(dig @8.8.8.8 +short "$DOMAIN" A 2>/dev/null | head -3)
        if [ -n "$ips" ]; then echo "DNS: OK (via 8.8.8.8)"; else return 1; fi
    else
        echo "DNS: OK"
    fi
    echo ""
}

check_direct() {
    echo "=== DIRECT CONNECTION CHECK ==="
    # HTTP
    code=$(curl -s --max-time "$CURL_TIMEOUT" -o /dev/null -w "%{http_code}" "$HTTP_URL" 2>&1)
    echo "HTTP ($HTTP_URL): $code"
    
    # HTTPS
    code=$(curl -s --max-time "$CURL_TIMEOUT" -o /dev/null -w "%{http_code}" "$TEST_URL" 2>&1)
    if echo "$code" | grep -q "^[0-9]\+$"; then
         if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
             echo "HTTPS ($TEST_URL): OK ($code)"
             echo "NOTE: It seems you are NOT blocked on this domain!"
         else
             echo "HTTPS ($TEST_URL): HTTP Code $code"
         fi
    else
         echo "HTTPS ($TEST_URL): BLOCKED (Error: $code)"
    fi
    echo ""
}

# --- TEST ENGINE ---

wait_for_port() {
    local port=$1
    local retries=30 # Increased wait time (3 sec)
    while [ $retries -gt 0 ]; do
        if nc -z -w 1 127.0.0.1 $port 2>/dev/null; then return 0; fi
        sleep 0.1
        ((retries--))
    done
    return 1
}

perform_test() {
    local engine_bin="$1"
    local engine_name="$2"
    local strategy_name="$3"
    local args="$4"
    
    # Ensure cleanup
    cleanup
    
    # Start Engine
    $engine_bin $args >/dev/null 2>&1 &
    ENGINE_PID=$!
    
    # Wait for start
    if ! wait_for_port "$SOCKS_PORT"; then
        echo "  [ ] $strategy_name: START ERROR (Port not open)"
        cleanup
        return 1
    fi
    
    # CURL Check
    # Important: Use --socks5-hostname to resolve DNS remotely
    local result
    result=$(curl -s --max-time "$CURL_TIMEOUT" \
        --proxy "socks5h://127.0.0.1:$SOCKS_PORT" \
        -o /dev/null -w "%{http_code}" "$TEST_URL" 2>&1)
    
    local ret=$?
    
    cleanup
    
    if [ $ret -eq 0 ] && echo "$result" | grep -q "^[23]"; then
        echo "  [+] $strategy_name: WORKING"
        WORKING_STRATEGIES+=("$engine_name: $strategy_name")
        return 0
    elif [ $ret -eq 28 ]; then
        echo "  [-] $strategy_name: TIMEOUT"
    elif [ "$result" == "000" ]; then
        echo "  [-] $strategy_name: BLOCKED (000)"
    else
        echo "  [-] $strategy_name: FAILED ($result)"
    fi
    return 1
}

# --- TEST SUITES ---

test_tpws_suite() {
    echo "=== TESTING TPWS STRATEGIES ==="
    # Standard Split
    perform_test "$TPWS" "tpws" "Split 1" "--socks --port $SOCKS_PORT --split-pos=1"
    perform_test "$TPWS" "tpws" "Split 2" "--socks --port $SOCKS_PORT --split-pos=2"
    perform_test "$TPWS" "tpws" "Split 3" "--socks --port $SOCKS_PORT --split-pos=3"
    
    # Disorder
    perform_test "$TPWS" "tpws" "Disorder 1" "--socks --port $SOCKS_PORT --split-pos=1 --disorder"
    perform_test "$TPWS" "tpws" "Disorder 3" "--socks --port $SOCKS_PORT --split-pos=3 --disorder"
    
    # MidSLD (Darkware Default)
    perform_test "$TPWS" "tpws" "Split+Disorder (MidSLD)" "--socks --port $SOCKS_PORT --split-pos=1,midsld --disorder"
    
    # TLS Rec
    perform_test "$TPWS" "tpws" "TLSRec (SNI)" "--socks --port $SOCKS_PORT --tlsrec=sniext"
    perform_test "$TPWS" "tpws" "TLSRec (MidSLD)" "--socks --port $SOCKS_PORT --tlsrec=midsld"
    perform_test "$TPWS" "tpws" "TLSRec+Split" "--socks --port $SOCKS_PORT --tlsrec=sniext --split-pos=1,midsld --disorder"
    
    # HostDot
    perform_test "$TPWS" "tpws" "HostDot" "--socks --port $SOCKS_PORT --hostdot"
    perform_test "$TPWS" "tpws" "TLSRec+OOB+HostDot" "--socks --port $SOCKS_PORT --tlsrec=sniext --split-pos=1,midsld --disorder --hostdot"
    
    echo ""
}

test_ciadpi_suite() {
    if [ ! -x "$CIADPI" ]; then return; fi
    
    echo "=== TESTING CIADPI (ByeDPI) STRATEGIES ==="
    
    # Basic Splits
    perform_test "$CIADPI" "ciadpi" "Split 1" "-p $SOCKS_PORT -s 1"
    perform_test "$CIADPI" "ciadpi" "Split 1+s" "-p $SOCKS_PORT -s 1+s"
    
    # Disorder
    perform_test "$CIADPI" "ciadpi" "Disorder 1" "-p $SOCKS_PORT -d 1"
    perform_test "$CIADPI" "ciadpi" "Disorder 3" "-p $SOCKS_PORT -d 3"
    perform_test "$CIADPI" "ciadpi" "Disorder 1+s" "-p $SOCKS_PORT -d 1+s"
    
    # OOB
    perform_test "$CIADPI" "ciadpi" "OOB" "-p $SOCKS_PORT --oob 1"
    perform_test "$CIADPI" "ciadpi" "OOB+Disorder" "-p $SOCKS_PORT --oob 1 --disorder 1"
    
    # Auto
    perform_test "$CIADPI" "ciadpi" "Auto (Torst)" "-p $SOCKS_PORT -A torst -d 1"
    perform_test "$CIADPI" "ciadpi" "Auto (Redirect)" "-p $SOCKS_PORT -A redirect -d 1"
    
    echo ""
}

# --- SUMMARY ---

print_summary() {
    echo "=== SUMMARY ==="
    count=${#WORKING_STRATEGIES[@]}
    if [ $count -gt 0 ]; then
        echo "Found $count working strategies!"
        for s in "${WORKING_STRATEGIES[@]}"; do
            echo "SUCCESS: $s"
        done
        echo ""
        echo "Suggested: Use matches from above in the app settings."
    else
        echo "NO WORKING STRATEGIES FOUND."
        echo "This could mean:"
        echo "1. ISP blocks IP/Port (not DPI)."
        echo "2. Protocol (QUIC/UDP) issues."
        echo "3. You need VPN."
    fi
    echo "=== DONE ==="
}

# --- MAIN ---

while [ $# -gt 0 ]; do
    case "$1" in
        --domain=*) DOMAIN="${1#*=}"; TEST_URL="https://${DOMAIN}"; HTTP_URL="http://${DOMAIN}";;
    esac
    shift
done

check_system
check_dns
check_direct
test_tpws_suite
test_ciadpi_suite
print_summary
