#!/bin/bash
#
# Darkware Zapret - macOS Diagnostics
# Диагностика блокировок и тестирование tpws стратегий
#

# Конфигурация
ZAPRET_BASE="${ZAPRET_BASE:-/opt/darkware-zapret}"
TPWS="${ZAPRET_BASE}/tpws/tpws"
CURL_TIMEOUT="${CURL_TIMEOUT:-5}"
SOCKS_PORT="${SOCKS_PORT:-19999}"
DOMAIN="${DOMAIN:-discord.com}"
TEST_URL="https://${DOMAIN}"
HTTP_URL="http://${DOMAIN}"

# Результаты
declare -a WORKING_STRATEGIES
TPWS_PID=""

# Очистка при выходе
cleanup() {
    if [ -n "$TPWS_PID" ] && kill -0 "$TPWS_PID" 2>/dev/null; then
        kill "$TPWS_PID" 2>/dev/null || true
        wait "$TPWS_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Проверка системы
check_system() {
    echo "=== SYSTEM INFO ==="
    echo "macOS: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
    echo "Arch: $(uname -m)"
    echo "curl: $(curl --version 2>/dev/null | head -1 | cut -d' ' -f1-2)"
    
    if [ -x "$TPWS" ]; then
        echo "tpws: OK"
    else
        echo "tpws: NOT FOUND"
        echo "ERROR: Install Darkware Zapret first"
        exit 1
    fi
    
    # Найти свободный порт
    for p in $(seq 19999 20010); do
        if ! nc -z 127.0.0.1 $p 2>/dev/null; then
            SOCKS_PORT=$p
            break
        fi
    done
    echo ""
}

# Проверка DNS
check_dns() {
    echo "=== DNS CHECK ==="
    
    local ips=$(dig +short "$DOMAIN" A 2>/dev/null | head -3)
    if [ -z "$ips" ]; then
        echo "DNS: FAILED - cannot resolve $DOMAIN"
        return 1
    fi
    
    echo "DNS: OK"
    for ip in $ips; do
        echo "  $DOMAIN -> $ip"
    done
    echo ""
}

# Проверка портов
check_ports() {
    echo "=== PORT CHECK ==="
    
    local ips=$(dig +short "$DOMAIN" A 2>/dev/null | head -2)
    local all_ok=1
    
    for ip in $ips; do
        if nc -z -w 2 "$ip" 443 2>/dev/null; then
            echo "$ip:443 - OPEN"
        else
            echo "$ip:443 - BLOCKED/TIMEOUT"
            all_ok=0
        fi
    done
    echo ""
}

# Тест без обхода
check_direct() {
    echo "=== DIRECT CONNECTION (no bypass) ==="
    
    # HTTP
    local http_code
    http_code=$(curl -s --max-time "$CURL_TIMEOUT" -o /dev/null -w "%{http_code}" "$HTTP_URL" 2>&1)
    local http_exit=$?
    
    if [ $http_exit -eq 0 ] && echo "$http_code" | grep -q "^[23]"; then
        echo "HTTP: OK"
    else
        echo "HTTP: FAILED (exit=$http_exit)"
    fi
    
    # HTTPS
    local https_code
    https_code=$(curl -s --max-time "$CURL_TIMEOUT" -o /dev/null -w "%{http_code}" "$TEST_URL" 2>&1)
    local https_exit=$?
    
    if [ $https_exit -eq 0 ] && echo "$https_code" | grep -q "^[23]"; then
        echo "HTTPS: OK (no DPI block detected)"
        HTTPS_WORKS=1
    else
        if [ $https_exit -eq 28 ]; then
            echo "HTTPS: TIMEOUT (DPI block detected)"
        else
            echo "HTTPS: FAILED (exit=$https_exit)"
        fi
        HTTPS_WORKS=0
    fi
    echo ""
}

# Запуск tpws
start_tpws() {
    local params="$@"
    
    if [ -n "$TPWS_PID" ] && kill -0 "$TPWS_PID" 2>/dev/null; then
        kill "$TPWS_PID" 2>/dev/null || true
        wait "$TPWS_PID" 2>/dev/null || true
    fi
    
    "$TPWS" --bind-addr=127.0.0.1 --port=$SOCKS_PORT --socks $params >/dev/null 2>&1 &
    TPWS_PID=$!
    sleep 0.3
    
    if ! kill -0 "$TPWS_PID" 2>/dev/null; then
        TPWS_PID=""
        return 1
    fi
    return 0
}

# Тест стратегии
test_strategy() {
    local name="$1"
    local params="$2"
    
    if ! start_tpws $params; then
        echo "  $name: ERROR (tpws failed)"
        return 1
    fi
    
    local result
    result=$(curl -s --max-time "$CURL_TIMEOUT" \
        --proxy "socks5://127.0.0.1:$SOCKS_PORT" \
        -o /dev/null -w "%{http_code}" "$TEST_URL" 2>&1)
    local code=$?
    
    if [ -n "$TPWS_PID" ]; then
        kill "$TPWS_PID" 2>/dev/null || true
        wait "$TPWS_PID" 2>/dev/null || true
        TPWS_PID=""
    fi
    
    if [ $code -eq 0 ] && echo "$result" | grep -q "^[23]"; then
        echo "  $name: OK"
        WORKING_STRATEGIES+=("$name")
        return 0
    else
        if [ $code -eq 28 ]; then
            echo "  $name: TIMEOUT"
        else
            echo "  $name: FAILED"
        fi
        return 1
    fi
}

# Тестирование стратегий
test_strategies() {
    echo "=== TPWS STRATEGY TESTING ==="
    echo "Domain: $DOMAIN"
    echo ""
    
    # Наши стратегии из приложения
    echo "Darkware Strategies:"
    test_strategy "Split+Disorder" "--split-pos=1,midsld --disorder"
    test_strategy "TLSRec+Split" "--tlsrec=sniext --split-pos=1,midsld --disorder"
    test_strategy "TLSRec MidSLD" "--tlsrec=midsld --split-pos=midsld --disorder"
    test_strategy "TLSRec+OOB" "--tlsrec=sniext --split-pos=1,midsld --disorder --hostdot"
    
    echo ""
    echo "Additional methods:"
    test_strategy "split-pos=2" "--split-pos=2"
    test_strategy "split-pos=2+disorder" "--split-pos=2 --disorder"
    test_strategy "tlsrec=sniext" "--tlsrec=sniext"
    test_strategy "tlsrec=midsld" "--tlsrec=midsld"
    echo ""
}

# Итоги
print_summary() {
    echo "=== SUMMARY ==="
    
    local count=${#WORKING_STRATEGIES[@]}
    
    if [ $count -gt 0 ]; then
        echo "Working strategies: $count"
        for s in "${WORKING_STRATEGIES[@]}"; do
            echo "  + $s"
        done
        echo ""
        
        # Рекомендация на основе наших стратегий
        local recommended=""
        for s in "${WORKING_STRATEGIES[@]}"; do
            case "$s" in
                "Split+Disorder"*) recommended="Split+Disorder"; break;;
                "TLSRec+Split"*) recommended="TLSRec+Split"; break;;
                "TLSRec MidSLD"*) recommended="TLSRec MidSLD"; break;;
                "TLSRec+OOB"*) recommended="TLSRec+OOB"; break;;
            esac
        done
        
        if [ -n "$recommended" ]; then
            echo "RECOMMENDED: Select '$recommended' strategy in Darkware Zapret"
        else
            echo "NOTE: Your ISP may require custom tpws parameters"
        fi
    else
        echo "NO WORKING STRATEGIES FOUND"
        echo ""
        echo "Possible reasons:"
        echo "  - ISP blocks by IP, not DPI"
        echo "  - Need different tpws parameters"
        echo "  - Try VPN instead"
    fi
    
    echo ""
    echo "=== END ==="
}

# Main
main() {
    echo "Darkware Zapret Diagnostics"
    echo "Domain: $DOMAIN"
    echo ""
    
    # Парсинг аргументов
    while [ $# -gt 0 ]; do
        case "$1" in
            --domain=*) 
                DOMAIN="${1#*=}"
                TEST_URL="https://${DOMAIN}"
                HTTP_URL="http://${DOMAIN}"
                ;;
            --timeout=*) CURL_TIMEOUT="${1#*=}" ;;
            --help)
                echo "Usage: $0 [--domain=DOMAIN] [--timeout=SEC]"
                exit 0
                ;;
        esac
        shift
    done
    
    check_system
    check_dns
    check_ports
    check_direct
    test_strategies
    print_summary
}

main "$@"
