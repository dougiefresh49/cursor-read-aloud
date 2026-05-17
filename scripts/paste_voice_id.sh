#!/usr/bin/env bash
#
# paste_voice_id.sh — Show a macOS dialog to paste an ElevenLabs voice ID.
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
SCRIPTS_DIR="$TTS_DIR/scripts"
LOG_FILE="$TTS_DIR/logs/hook.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] paste_voice: $*" >> "$LOG_FILE" 2>/dev/null || true; }

RESULT=$(osascript -e '
tell application "System Events"
    set theResponse to display dialog "Paste an ElevenLabs Voice ID:" default answer "" with title "Set Voice ID" buttons {"Cancel", "Set Voice"} default button "Set Voice"
    return text returned of theResponse
end tell
' 2>/dev/null) || exit 0

VOICE_ID=$(echo "$RESULT" | tr -d '[:space:]')

if [ -z "$VOICE_ID" ]; then
    log "Empty voice ID from dialog"
    exit 0
fi

"$SCRIPTS_DIR/set_voice.sh" "$VOICE_ID"
log "Set voice from paste dialog: $VOICE_ID"
