#!/usr/bin/env bash
#
# play.sh — Clean a queued response, synthesize via Piper HTTP, play via afplay.
# Falls back to macOS `say` if Piper is unreachable.
#
# Usage: play.sh <queue-file>
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
CONFIG="$TTS_DIR/config.json"
SCRIPTS_DIR="$TTS_DIR/scripts"
PID_FILE="$TTS_DIR/.playback-pid"
PLAYBACK_FILE_REF="$TTS_DIR/.playback-file"
PAUSED_FLAG="$TTS_DIR/.playback-paused"
AUDIO_REF="$TTS_DIR/.playback-audio"
PLAYED_DIR="$TTS_DIR/played"
LOG_FILE="$TTS_DIR/logs/hook.log"
WAV_FILE="/tmp/cursor-tts-current.wav"

mkdir -p "$PLAYED_DIR" "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] play: $*" >> "$LOG_FILE"; }

die() { log "ERROR: $*"; echo "ERROR: $*" >&2; exit 1; }

# ── Parse arguments ───────────────────────────────────────────────
QUEUE_FILE="${1:-}"
if [ -z "$QUEUE_FILE" ]; then
    die "Usage: play.sh <queue-file>"
fi
if [ ! -f "$QUEUE_FILE" ]; then
    die "Queue file not found: $QUEUE_FILE"
fi

# ── Kill any existing playback ────────────────────────────────────
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        log "Stopping previous playback (PID $OLD_PID)"
        kill "$OLD_PID" 2>/dev/null || true
        wait "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi
rm -f "$PAUSED_FLAG"

finish_playback_if_owner() {
    local play_pid="$1"
    if [ ! -f "$PID_FILE" ]; then
        log "Playback superseded (no pid file) — not moving queue file"
        return 1
    fi
    local stored
    stored=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ "$stored" != "$play_pid" ]; then
        log "Playback superseded (pid $stored vs $play_pid) — not moving queue file"
        return 1
    fi
    rm -f "$PID_FILE" "$PAUSED_FLAG" "$AUDIO_REF" "$PLAYBACK_FILE_REF"
    mv "$QUEUE_FILE" "$PLAYED_DIR/"
    log "Finished: $(basename "$QUEUE_FILE")"
    return 0
}

# ── Extract text from queue file ──────────────────────────────────
RAW_TEXT=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('text', ''))
" "$QUEUE_FILE") || die "Failed to read text from $QUEUE_FILE"

if [ -z "$RAW_TEXT" ]; then
    die "No text in queue file: $QUEUE_FILE"
fi

# ── Clean text ────────────────────────────────────────────────────
CLEANED=$(echo "$RAW_TEXT" | python3 "$SCRIPTS_DIR/clean_text.py" 2>"$TTS_DIR/logs/clean.log") || die "Text cleaning failed"

if [ -z "$CLEANED" ]; then
    log "No speakable text after cleaning: $QUEUE_FILE"
    mv "$QUEUE_FILE" "$PLAYED_DIR/"
    exit 0
fi

# ── Read config ───────────────────────────────────────────────────
if [ -f "$CONFIG" ]; then
    PIPER_PORT=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('piper_port', 5111))")
    SPEAKER_ID=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('speaker_id', 0))")
    DEFAULT_SPEED=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('default_speed', 1.0))")
else
    PIPER_PORT=5111
    SPEAKER_ID=0
    DEFAULT_SPEED=1.0
fi

LENGTH_SCALE=$(python3 -c "print(round(1.0 / $DEFAULT_SPEED, 4))")

# ── Synthesize audio ──────────────────────────────────────────────
PIPER_URL="http://localhost:$PIPER_PORT"
USE_PIPER=true

PAYLOAD=$(python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps({
    'text': text,
    'speaker_id': $SPEAKER_ID,
    'length_scale': $LENGTH_SCALE
}))
" <<< "$CLEANED")

HTTP_CODE=$(curl -s -o "$WAV_FILE" -w "%{http_code}" \
    -X POST -H 'Content-Type: application/json' \
    -d "$PAYLOAD" \
    "$PIPER_URL" 2>/dev/null) || HTTP_CODE="000"

if [ "$HTTP_CODE" != "200" ]; then
    USE_PIPER=false
    log "Piper HTTP unavailable (HTTP $HTTP_CODE) — falling back to macOS say"

    AIFF_FILE="/tmp/cursor-tts-current.aiff"
    say -o "$AIFF_FILE" "$CLEANED" 2>/dev/null || die "macOS say failed"

    printf '%s' "$QUEUE_FILE" > "$PLAYBACK_FILE_REF"
    printf '%s' "$AIFF_FILE" > "$AUDIO_REF"
    afplay "$AIFF_FILE" &
    PLAY_PID=$!
    echo "$PLAY_PID" > "$PID_FILE"

    log "Playing via macOS say (PID $PLAY_PID)"
    wait "$PLAY_PID" 2>/dev/null || true
    if finish_playback_if_owner "$PLAY_PID"; then
        exit 0
    fi
    exit 0
fi

# ── Play via afplay ───────────────────────────────────────────────
log "Playing via Piper (speaker=$SPEAKER_ID, speed=${DEFAULT_SPEED}x, length_scale=$LENGTH_SCALE)"

printf '%s' "$QUEUE_FILE" > "$PLAYBACK_FILE_REF"
printf '%s' "$WAV_FILE" > "$AUDIO_REF"
afplay "$WAV_FILE" &
PLAY_PID=$!
echo "$PLAY_PID" > "$PID_FILE"

log "Playback started (PID $PLAY_PID, file=$(basename "$QUEUE_FILE"))"

wait "$PLAY_PID" 2>/dev/null || true
finish_playback_if_owner "$PLAY_PID" || true
