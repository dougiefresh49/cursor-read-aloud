#!/usr/bin/env bash
#
# set_listening.sh — Pause/resume TTS: skip hook ingestion, unload Piper to free RAM.
#
# Usage: set_listening.sh on|off|toggle
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
FLAG="$TTS_DIR/listening.enabled"
PLIST="$HOME/Library/LaunchAgents/com.local.piper-tts-server.plist"
LABEL="com.local.piper-tts-server"
SCRIPTS_DIR="$TTS_DIR/scripts"
CONFIG="$TTS_DIR/config.json"
LOG_FILE="$TTS_DIR/logs/hook.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] set_listening: $*" >> "$LOG_FILE" 2>/dev/null || true; }

mkdir -p "$TTS_DIR" "$(dirname "$LOG_FILE")"

piper_port() {
    if [ -f "$CONFIG" ]; then
        python3 -c "import json; print(json.load(open('$CONFIG')).get('piper_port', 5111))" 2>/dev/null || echo "5111"
    else
        echo "5111"
    fi
}

wait_for_piper() {
    local port
    port="$(piper_port)"
    local i
    for i in $(seq 1 20); do
        if curl -s "http://localhost:${port}/voices" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    log "Piper did not respond on port ${port} within 20s (may still be starting)"
}

MODE="${1:-toggle}"

case "$MODE" in
    on|1|start|true)
        echo 1 > "$FLAG"
        log "Listening ON"
        if [ -f "$PLIST" ]; then
            if launchctl list 2>/dev/null | grep -q "$LABEL"; then
                log "LaunchAgent already loaded"
            else
                launchctl load "$PLIST" 2>/dev/null || {
                    log "launchctl load failed — try: launchctl load $PLIST"
                }
                wait_for_piper
            fi
        else
            log "No plist at $PLIST — run scripts/setup.sh"
        fi
        ;;
    off|0|stop|false)
        echo 0 > "$FLAG"
        log "Listening OFF"
        if [ -x "$SCRIPTS_DIR/stop.sh" ]; then
            "$SCRIPTS_DIR/stop.sh" 2>/dev/null || true
        fi
        if [ -f "$PLIST" ]; then
            launchctl unload "$PLIST" 2>/dev/null || true
            log "Piper LaunchAgent unloaded"
        fi
        ;;
    toggle)
        cur=1
        if [ -f "$FLAG" ]; then
            case "$(tr -d ' \n' < "$FLAG")" in
                0|false|FALSE|off) cur=0 ;;
            esac
        fi
        if [ "$cur" -eq 1 ]; then
            exec "$0" off
        else
            exec "$0" on
        fi
        ;;
    *)
        echo "Usage: $0 on|off|toggle" >&2
        exit 1
        ;;
esac

exit 0
