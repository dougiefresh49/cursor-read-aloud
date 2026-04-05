#!/usr/bin/env bash
#
# quit.sh — Stop listening / playback, then quit SwiftBar.
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
SCRIPTS_DIR="$TTS_DIR/scripts"
LOG_FILE="$TTS_DIR/logs/hook.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] quit: $*" >> "$LOG_FILE" 2>/dev/null || true; }

if [ -x "$SCRIPTS_DIR/set_listening.sh" ]; then
    "$SCRIPTS_DIR/set_listening.sh" off || true
else
    log "set_listening.sh not found — skipping listen shutdown"
fi

osascript -e 'tell application "SwiftBar" to quit' 2>/dev/null || \
    osascript -e 'tell application id "com.RomanKhramov.SwiftBar" to quit' 2>/dev/null || \
    log "Could not quit SwiftBar via AppleScript"

exit 0
