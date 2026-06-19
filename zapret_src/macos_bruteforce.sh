#!/bin/bash
#
# Darkware Zapret - Strategy Bruteforce Scanner
# Перебирает ВСЕ возможные комбинации параметров для поиска рабочей стратегии
#

# Configuration
ZAPRET_BASE="${ZAPRET_BASE:-/opt/darkware-zapret}"
TPWS="${ZAPRET_BASE}/tpws/tpws"
CIADPI="${ZAPRET_BASE}/byedpi/ciadpi"
CURL_TIMEOUT="${CURL_TIMEOUT:-3}"
SOCKS_PORT="${SOCKS_PORT:-19998}"
DOMAIN="${DOMAIN:-discord.com}"
TEST_URL="https://${DOMAIN}"

# Global State
declare -a WORKING_STRATEGIES
ENGINE_PID=""
TOTAL_TESTS=0
PASSED_TESTS=0

# Cleanup
cleanup() {
    if [ -n "$ENGINE_PID" ]; then
        kill -9 "$ENGINE_PID" 2>/dev/null || true
        wait "$ENGINE_PID" 2>/dev/null || true
        ENGINE_PID=""
    fi
}
trap cleanup EXIT INT TERM

# Find free port
find_free_port() {
    for p in $(seq 19998 20100); do
        if ! nc -z -w 1 127.0.0.1 $p 2>/dev/null; then
            SOCKS_PORT=$p
            return 0
        fi
    done
    return 1
}

# Wait for port
wait_for_port() {
    local port=$1
    local retries=20
    while [ $retries -gt 0 ]; do
        if nc -z -w 1 127.0.0.1 $port 2>/dev/null; then return 0; fi
        sleep 0.1
        ((retries--))
    done
    return 1
}

# Test function
perform_test() {
    local engine_bin="$1"
    local engine_name="$2"
    local strategy_name="$3"
    local args="$4"

    ((TOTAL_TESTS++))
    cleanup

    # Start engine
    $engine_bin $args >/dev/null 2>&1 &
    ENGINE_PID=$!

    if ! wait_for_port "$SOCKS_PORT"; then
        echo "  [X] $strategy_name: START FAILED"
        cleanup
        return 1
    fi

    # Test connection
    local result
    result=$(curl -s --max-time "$CURL_TIMEOUT" \
        --proxy "socks5h://127.0.0.1:$SOCKS_PORT" \
        -o /dev/null -w "%{http_code}" "$TEST_URL" 2>&1)
    local ret=$?

    cleanup

    if [ $ret -eq 0 ] && echo "$result" | grep -q "^[23]"; then
        echo "  [OK] $strategy_name: WORKING (HTTP $result)"
        WORKING_STRATEGIES+=("$engine_name|$strategy_name|$args")
        ((PASSED_TESTS++))
        return 0
    elif [ $ret -eq 28 ]; then
        echo "  [X] $strategy_name: TIMEOUT"
    else
        echo "  [X] $strategy_name: FAILED ($result)"
    fi
    return 1
}

# =====================================================
# TPWS BRUTEFORCE
# =====================================================
bruteforce_tpws() {
    echo ""
    echo "================================================================"
    echo "              TPWS STRATEGY BRUTEFORCE"
    echo "================================================================"
    echo ""

    echo "--- Phase 1: Basic split positions ---"
    for pos in "1" "2" "3" "1,midsld" "midsld"; do
        perform_test "$TPWS" "tpws" "Split $pos" "--socks --port $SOCKS_PORT --split-pos=$pos"
    done

    echo ""
    echo "--- Phase 2: Split + Disorder combinations ---"
    for pos in "1" "2" "3" "1,midsld" "midsld"; do
        perform_test "$TPWS" "tpws" "Split $pos + Disorder" "--socks --port $SOCKS_PORT --split-pos=$pos --disorder"
    done

    echo ""
    echo "--- Phase 3: TLSRec variations ---"
    for rec in "sniext" "midsld"; do
        perform_test "$TPWS" "tpws" "TLSRec=$rec" "--socks --port $SOCKS_PORT --tlsrec=$rec"
        perform_test "$TPWS" "tpws" "TLSRec=$rec + Split" "--socks --port $SOCKS_PORT --tlsrec=$rec --split-pos=1,midsld"
        perform_test "$TPWS" "tpws" "TLSRec=$rec + Disorder" "--socks --port $SOCKS_PORT --tlsrec=$rec --split-pos=1,midsld --disorder"
    done

    echo ""
    echo "--- Phase 4: OOB combinations ---"
    perform_test "$TPWS" "tpws" "OOB" "--socks --port $SOCKS_PORT --oob"
    perform_test "$TPWS" "tpws" "OOB + Disorder" "--socks --port $SOCKS_PORT --split-pos=1 --disorder --oob"
    perform_test "$TPWS" "tpws" "OOB + TLSRec" "--socks --port $SOCKS_PORT --tlsrec=sniext --oob"

    echo ""
    echo "--- Phase 5: HostDot combinations ---"
    perform_test "$TPWS" "tpws" "HostDot" "--socks --port $SOCKS_PORT --hostdot"
    perform_test "$TPWS" "tpws" "HostDot + Split" "--socks --port $SOCKS_PORT --hostdot --split-pos=1,midsld"
    perform_test "$TPWS" "tpws" "HostDot + Disorder" "--socks --port $SOCKS_PORT --hostdot --split-pos=1,midsld --disorder"

    echo ""
    echo "--- Phase 6: Full combos (aggressive) ---"
    perform_test "$TPWS" "tpws" "Full Combo 1" "--socks --port $SOCKS_PORT --tlsrec=sniext --split-pos=1,midsld --disorder --oob"
    perform_test "$TPWS" "tpws" "Full Combo 2" "--socks --port $SOCKS_PORT --tlsrec=midsld --split-pos=midsld --disorder"
    perform_test "$TPWS" "tpws" "Full Combo 3" "--socks --port $SOCKS_PORT --tlsrec=sniext --split-pos=1,midsld --disorder --hostdot"
    perform_test "$TPWS" "tpws" "Full Combo 4" "--socks --port $SOCKS_PORT --tlsrec=sniext --split-pos=1,midsld --disorder --oob --hostdot"
}

# =====================================================
# CIADPI BRUTEFORCE
# =====================================================
bruteforce_ciadpi() {
    if [ ! -x "$CIADPI" ]; then
        echo "ciadpi not found, skipping"
        return
    fi

    echo ""
    echo "================================================================"
    echo "             CIADPI STRATEGY BRUTEFORCE"
    echo "================================================================"
    echo ""

    echo "--- Phase 1: Basic split/disorder ---"
    perform_test "$CIADPI" "ciadpi" "Split 1" "-p $SOCKS_PORT -s 1"
    perform_test "$CIADPI" "ciadpi" "Split 1+s (SNI)" "-p $SOCKS_PORT -s 1+s"
    perform_test "$CIADPI" "ciadpi" "Disorder 1" "-p $SOCKS_PORT -d 1"
    perform_test "$CIADPI" "ciadpi" "Disorder 1+s" "-p $SOCKS_PORT -d 1+s"
    perform_test "$CIADPI" "ciadpi" "Disorder 3" "-p $SOCKS_PORT -d 3"
    perform_test "$CIADPI" "ciadpi" "Disorder 3+s" "-p $SOCKS_PORT -d 3+s"

    echo ""
    echo "--- Phase 2: OOB variations ---"
    perform_test "$CIADPI" "ciadpi" "OOB 1" "-p $SOCKS_PORT -o 1"
    perform_test "$CIADPI" "ciadpi" "OOB 1+s" "-p $SOCKS_PORT -o 1+s"
    perform_test "$CIADPI" "ciadpi" "OOB 3+s" "-p $SOCKS_PORT -o 3+s"
    perform_test "$CIADPI" "ciadpi" "Disoob 1" "-p $SOCKS_PORT -q 1"
    perform_test "$CIADPI" "ciadpi" "Disoob 1+s" "-p $SOCKS_PORT -q 1+s"

    echo ""
    echo "--- Phase 3: TLSRec variations ---"
    perform_test "$CIADPI" "ciadpi" "TLSRec 1+s" "-p $SOCKS_PORT -r 1+s"
    perform_test "$CIADPI" "ciadpi" "TLSRec 3+s" "-p $SOCKS_PORT -r 3+s"

    echo ""
    echo "--- Phase 4: Combinations ---"
    perform_test "$CIADPI" "ciadpi" "Disorder + OOB" "-p $SOCKS_PORT -d 1 -o 1+s"
    perform_test "$CIADPI" "ciadpi" "Disorder + TLSRec" "-p $SOCKS_PORT -d 1 -r 1+s"
    perform_test "$CIADPI" "ciadpi" "OOB + TLSRec" "-p $SOCKS_PORT -o 1+s -r 1+s"
    perform_test "$CIADPI" "ciadpi" "Split + Disorder" "-p $SOCKS_PORT -s 1 -d 1+s"
    perform_test "$CIADPI" "ciadpi" "Split + OOB" "-p $SOCKS_PORT -s 1 -o 1+s"
    perform_test "$CIADPI" "ciadpi" "Disoob + Disorder" "-p $SOCKS_PORT -q 1 -d 1+s"

    # NOTE: Auto modes (-A) removed - they are blocking detectors, not strategies.
    # They wait for timeout/reset to detect blocking, which doesn't work in single-request tests.

    echo ""
    echo "--- Phase 5: Full combos ---"
    perform_test "$CIADPI" "ciadpi" "Full: d+o+r" "-p $SOCKS_PORT -d 1 -o 1+s -r 1+s"
    perform_test "$CIADPI" "ciadpi" "Full: s+d+o" "-p $SOCKS_PORT -s 1 -d 1+s -o 1+s"
    perform_test "$CIADPI" "ciadpi" "Full: q+d+r" "-p $SOCKS_PORT -q 1 -d 1+s -r 1+s"

    echo ""
    echo "--- Phase 6: UDP fake (for Discord voice) ---"
    perform_test "$CIADPI" "ciadpi" "UDP fake 3" "-p $SOCKS_PORT -d 1 -a 3"
    perform_test "$CIADPI" "ciadpi" "UDP fake 5" "-p $SOCKS_PORT -d 1 -a 5"
    perform_test "$CIADPI" "ciadpi" "UDP fake + OOB" "-p $SOCKS_PORT -o 1+s -a 5"
    perform_test "$CIADPI" "ciadpi" "Full + UDP" "-p $SOCKS_PORT -d 1 -o 1+s -r 1+s -a 5"
}

# =====================================================
# SAVE TO JSON
# =====================================================
save_to_json() {
    local json_file="/tmp/darkware_strategies.json"

    if [ ${#WORKING_STRATEGIES[@]} -eq 0 ]; then
        # Empty array
        echo "[]" > "$json_file"
        return
    fi

    # Build JSON array
    echo "[" > "$json_file"
    local first=true

    for entry in "${WORKING_STRATEGIES[@]}"; do
        IFS='|' read -r engine name args <<< "$entry"

        # Remove test-only listener options. The app adds the runtime port itself.
        local clean_args
        if [ "$engine" = "ciadpi" ]; then
            clean_args=$(echo "$args" | sed -E "s/(^| )-p[ =]?$SOCKS_PORT( |$)/ /g" | xargs)
        else
            clean_args=$(echo "$args" | sed -E "s/(^| )--socks( |$)/ /g; s/(^| )--port[ =]?$SOCKS_PORT( |$)/ /g; s/(^| )--port=$SOCKS_PORT( |$)/ /g" | xargs)
        fi

        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$json_file"
        fi

        # Escape quotes in name and args
        name=$(echo "$name" | sed 's/"/\\"/g')
        clean_args=$(echo "$clean_args" | sed 's/"/\\"/g')

        printf '  {"engine": "%s", "name": "%s", "args": "%s"}' "$engine" "$name" "$clean_args" >> "$json_file"
    done

    echo "" >> "$json_file"
    echo "]" >> "$json_file"
}

# =====================================================
# SUMMARY
# =====================================================
print_summary() {
    echo ""
    echo "================================================================"
    echo "                    BRUTEFORCE RESULTS"
    echo "================================================================"
    echo ""
    echo "Domain tested: $DOMAIN"
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo ""

    # Save results to JSON for app import
    save_to_json

    if [ ${#WORKING_STRATEGIES[@]} -eq 0 ]; then
        echo "================================================================"
        echo "  NO WORKING STRATEGIES FOUND"
        echo "================================================================"
        echo ""
        echo "Possible reasons:"
        echo "  1. ISP blocks by IP (not DPI) - need VPN"
        echo "  2. Domain is completely blocked"
        echo "  3. Try with longer timeout: CURL_TIMEOUT=10"
        echo "  4. Check if IPv6 is causing issues"
    else
        echo "================================================================"
        echo "  WORKING STRATEGIES FOUND: ${#WORKING_STRATEGIES[@]}"
        echo "================================================================"
        echo ""

        for entry in "${WORKING_STRATEGIES[@]}"; do
            IFS='|' read -r engine name args <<< "$entry"
            echo "[OK] [$engine] $name"
            echo "     Args: $args"
            echo ""
        done

        echo "Recommendation: Use the simplest working strategy for best performance."
        echo ""
        echo "Click 'Save Strategies' to add working strategies to the app."
    fi

    echo ""
    echo "--- Bruteforce scan complete ---"
}

# =====================================================
# MAIN
# =====================================================

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --domain=*)
            DOMAIN="${1#*=}"
            TEST_URL="https://${DOMAIN}"
            ;;
        --timeout=*)
            CURL_TIMEOUT="${1#*=}"
            ;;
    esac
    shift
done

echo "================================================================"
echo "       DARKWARE ZAPRET - STRATEGY BRUTEFORCE SCANNER"
echo "================================================================"
echo ""
echo "Target: $DOMAIN"
echo "Timeout: ${CURL_TIMEOUT}s"
echo ""

# Find free port
if ! find_free_port; then
    echo "Error: Could not find free port"
    exit 1
fi
echo "Using port: $SOCKS_PORT"
echo ""

# Check binaries
if [ ! -x "$TPWS" ]; then
    echo "Error: tpws not found at $TPWS"
    exit 1
fi
echo "tpws: OK"

if [ -x "$CIADPI" ]; then
    echo "ciadpi: OK"
else
    echo "ciadpi: NOT FOUND (will skip)"
fi
echo ""

# Run tests
bruteforce_tpws
bruteforce_ciadpi
print_summary
