#!/usr/bin/env bash
#
# stop.sh — Stop any active TTS playback.
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
PID_FILE="$TTS_DIR/.playback-pid"
LOG_FILE="$TTS_DIR/logs/hook.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] stop: $*" >> "$LOG_FILE" 2>/dev/null; }

if [ ! -f "$PID_FILE" ]; then
    log "No active playback"
    exit 0
fi

PID=$(cat "$PID_FILE" 2>/dev/null || true)

if [ -z "$PID" ]; then
    rm -f "$PID_FILE"
    exit 0
fi

if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    log "Stopped playback (PID $PID)"
else
    log "Process $PID already finished"
fi

rm -f "$PID_FILE"
