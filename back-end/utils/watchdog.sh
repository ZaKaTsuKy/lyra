#!/usr/bin/env bash
# ============================================
# OMNI MONITOR - Watchdog Script v1.0
# ============================================
# Purpose: Monitor Julia backend health and enforce resource limits.
# Usage: ./watchdog.sh (run in background with nohup or systemd)
# ============================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_JL="$SCRIPT_DIR/main.jl"
LOG_FILE="$SCRIPT_DIR/watchdog.log"
HEALTH_URL="${HEALTH_URL:-http://localhost:8080/health}"
HEALTH_TIMEOUT=5
RAM_LIMIT_KB=$((1024 * 1024))  # 1GB in KB
CHECK_INTERVAL=60

# ============================================
# Logging
# ============================================
log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# ============================================
# Server Management
# ============================================
start_server() {
    log "Starting Julia server..."
    cd "$SCRIPT_DIR"
    nohup julia "$MAIN_JL" >> "$LOG_FILE" 2>&1 &
    log "Server started with PID $!"
}

# ============================================
# Health Checks
# ============================================
check_health() {
    curl -sf --max-time "$HEALTH_TIMEOUT" "$HEALTH_URL" > /dev/null 2>&1
}

get_julia_pid() {
    pgrep -f "julia.*main.jl" | head -1 || echo ""
}

get_rss_kb() {
    local pid="$1"
    ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0"
}

# ============================================
# Main Loop
# ============================================
main() {
    log "=== Watchdog started ==="
    log "Configuration:"
    log "  MAIN_JL: $MAIN_JL"
    log "  HEALTH_URL: $HEALTH_URL"
    log "  RAM_LIMIT_KB: $RAM_LIMIT_KB"
    log "  CHECK_INTERVAL: ${CHECK_INTERVAL}s"

    # Initial startup
    start_server
    sleep 10  # Grace period for startup

    while true; do
        PID=$(get_julia_pid)

        # Check 1: Process exists?
        if [[ -z "$PID" ]]; then
            log "ALERT: No Julia process found. Restarting..."
            start_server
            sleep 10
            continue
        fi

        # Check 2: RAM limit exceeded?
        RSS=$(get_rss_kb "$PID")
        if (( RSS > RAM_LIMIT_KB )); then
            log "ALERT: RAM limit exceeded (${RSS}KB > ${RAM_LIMIT_KB}KB). Killing PID $PID..."
            kill -9 "$PID" 2>/dev/null || true
            sleep 2
            start_server
            sleep 10
            continue
        fi

        # Check 3: Health endpoint responsive?
        if ! check_health; then
            log "ALERT: Health check failed (no response from $HEALTH_URL). Killing PID $PID..."
            kill -9 "$PID" 2>/dev/null || true
            sleep 2
            start_server
            sleep 10
            continue
        fi

        # All checks passed
        sleep "$CHECK_INTERVAL"
    done
}

# Run main loop
main
