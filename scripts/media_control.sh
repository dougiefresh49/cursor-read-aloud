#!/usr/bin/env bash
#
# media_control.sh — Smart Play/Pause media control for TTS + queue.
# If playback PID is active → toggle pause (pause.sh).
# Else if queue has items → play latest (play_latest.sh).
# Else no-op (exit 0).
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
SCRIPTS_DIR="$TTS_DIR/scripts"
PID_FILE="$TTS_DIR/.playback-pid"
QUEUE_DIR="$TTS_DIR/queue"
LOG_FILE="$TTS_DIR/logs/hook.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] media_control: $*" >> "$LOG_FILE" 2>/dev/null || true; }

mkdir -p "$(dirname "$LOG_FILE")"

if [ -f "$PID_FILE" ]; then
    PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        log "Active playback → pause toggle"
        exec "$SCRIPTS_DIR/pause.sh"
    fi
fi

if [ -d "$QUEUE_DIR" ] && [ -n "$(find "$QUEUE_DIR" -maxdepth 1 -name '*.json' -print -quit 2>/dev/null)" ]; then
    log "Idle with queue → play latest"
    exec "$SCRIPTS_DIR/play_latest.sh"
fi

log "Idle, empty queue — no-op"
exit 0
