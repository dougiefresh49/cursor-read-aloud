#!/usr/bin/env bash
#
# play.sh — Process a queued response via Gemini + ElevenLabs TTS, play via afplay.
# Falls back to macOS `say` if ElevenLabs is unreachable.
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
AUDIO_FILE="/tmp/cursor-tts-current.mp3"
PROCESSING_DIR="$TTS_DIR/.processing"

mkdir -p "$PLAYED_DIR" "$(dirname "$LOG_FILE")" "$PROCESSING_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] play: $*" >> "$LOG_FILE"; }

die() { log "ERROR: $*"; echo "ERROR: $*" >&2; exit 1; }

# ── Load env ─────────────────────────────────────────────────────
source "$SCRIPTS_DIR/load_env.sh" 2>/dev/null || true

# ── Parse arguments ───────────────────────────────────────────────
QUEUE_FILE="${1:-}"
if [ -z "$QUEUE_FILE" ]; then
    die "Usage: play.sh <queue-file>"
fi
if [ ! -f "$QUEUE_FILE" ]; then
    die "Queue file not found: $QUEUE_FILE"
fi

# ── Mark as processing (prevents double-play from notification + menu) ─
QUEUE_BASENAME=$(basename "$QUEUE_FILE")
PROCESSING_MARKER="$PROCESSING_DIR/$QUEUE_BASENAME"
if [ -f "$PROCESSING_MARKER" ]; then
    MARKER_PID=$(cat "$PROCESSING_MARKER" 2>/dev/null || true)
    if [ -n "$MARKER_PID" ] && kill -0 "$MARKER_PID" 2>/dev/null; then
        log "Already processing $QUEUE_BASENAME (PID $MARKER_PID) — skipping"
        exit 0
    fi
fi
echo $$ > "$PROCESSING_MARKER"
cleanup_processing() { rm -f "$PROCESSING_MARKER"; }
trap cleanup_processing EXIT

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

# ── Process text via Gemini (falls back to clean_text.py) ────────
PROCESSED=$(echo "$RAW_TEXT" | python3 "$SCRIPTS_DIR/gemini_process.py" 2>"$TTS_DIR/logs/clean.log") || die "Text processing failed"

if [ -z "$PROCESSED" ]; then
    log "No speakable text after processing: $QUEUE_FILE"
    mv "$QUEUE_FILE" "$PLAYED_DIR/"
    exit 0
fi

# ── Read config ───────────────────────────────────────────────────
VOICE_ID=""
MODEL_ID="eleven_v3"
DEFAULT_SPEED="1.25"
if [ -f "$CONFIG" ]; then
    VOICE_ID=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('elevenlabs_voice_id', ''))" 2>/dev/null || echo "")
    MODEL_ID=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('elevenlabs_model_id', 'eleven_v3'))" 2>/dev/null || echo "eleven_v3")
    DEFAULT_SPEED=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('default_speed', 1.25))" 2>/dev/null || echo "1.25")
fi

# ── Check for per-session voice override ─────────────────────────
SESSION_VOICES="$TTS_DIR/session_voices.json"
QUEUE_SESSION_ID=$(python3 -c "import json; print(json.load(open('$QUEUE_FILE')).get('conversation_id', ''))" 2>/dev/null || echo "")
if [ -n "$QUEUE_SESSION_ID" ] && [ -f "$SESSION_VOICES" ]; then
    SESSION_VOICE=$(python3 -c "import json; print(json.load(open('$SESSION_VOICES')).get('$QUEUE_SESSION_ID', ''))" 2>/dev/null || echo "")
    if [ -n "$SESSION_VOICE" ]; then
        log "Using session voice override: $SESSION_VOICE (session $QUEUE_SESSION_ID)"
        VOICE_ID="$SESSION_VOICE"
    fi
fi

# ── Validate we have what we need ─────────────────────────────────
ELEVENLABS_API_KEY="${ELEVENLABS_API_KEY:-}"
if [ -z "$ELEVENLABS_API_KEY" ]; then
    log "No ELEVENLABS_API_KEY — falling back to macOS say"
fi

if [ -z "$VOICE_ID" ]; then
    log "No voice_id configured — falling back to macOS say"
fi

# ── Synthesize audio ──────────────────────────────────────────────
USE_ELEVENLABS=true
if [ -z "$ELEVENLABS_API_KEY" ] || [ -z "$VOICE_ID" ]; then
    USE_ELEVENLABS=false
fi

if [ "$USE_ELEVENLABS" = true ]; then
    # ElevenLabs v3 has a 5000 char limit — chunk if needed
    CHAR_COUNT=${#PROCESSED}

    SPEED_VAL=$(python3 -c "print(min(1.2, max(0.7, $DEFAULT_SPEED)))")
    AFPLAY_RATE=$(python3 -c "
s = $DEFAULT_SPEED
el_speed = min(1.2, max(0.7, s))
print(round(s / el_speed, 4) if s > 1.2 else 1.0)
")

    if [ "$CHAR_COUNT" -le 5000 ]; then
        # Single request
        PAYLOAD=$(python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps({
    'text': text,
    'model_id': '$MODEL_ID',
    'voice_settings': {
        'stability': 0.4,
        'similarity_boost': 0.75,
        'style': 0.15,
        'speed': $SPEED_VAL
    }
}))
" <<< "$PROCESSED")

        HTTP_CODE=$(curl -s -o "$AUDIO_FILE" -w "%{http_code}" \
            -X POST "https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}?output_format=mp3_44100_128" \
            -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" 2>/dev/null) || HTTP_CODE="000"

        if [ "$HTTP_CODE" != "200" ]; then
            log "ElevenLabs HTTP $HTTP_CODE — falling back to macOS say"
            # Check if we got a JSON error body
            if [ -f "$AUDIO_FILE" ] && [ "$(head -c 1 "$AUDIO_FILE" 2>/dev/null)" = "{" ]; then
                ERR_MSG=$(python3 -c "import json; print(json.load(open('$AUDIO_FILE')).get('detail',{}).get('message','unknown'))" 2>/dev/null || echo "unknown")
                log "ElevenLabs error: $ERR_MSG"
            fi
            USE_ELEVENLABS=false
        fi
    else
        # Chunk the text at sentence boundaries
        log "Text is ${CHAR_COUNT} chars — chunking for ElevenLabs"
        CHUNK_DIR="/tmp/cursor-tts-chunks"
        rm -rf "$CHUNK_DIR"
        mkdir -p "$CHUNK_DIR"

        python3 -c "
import sys, re
text = sys.stdin.read()
chunks = []
current = ''
for sentence in re.split(r'(?<=[.!?])\s+', text):
    if len(current) + len(sentence) + 1 > 4800 and current:
        chunks.append(current.strip())
        current = sentence
    else:
        current = current + ' ' + sentence if current else sentence
if current.strip():
    chunks.append(current.strip())
for i, chunk in enumerate(chunks):
    with open(f'/tmp/cursor-tts-chunks/chunk_{i:03d}.txt', 'w') as f:
        f.write(chunk)
print(len(chunks))
" <<< "$PROCESSED" > /dev/null

        CHUNK_FILES=$(find "$CHUNK_DIR" -name '*.txt' | sort)
        CHUNK_INDEX=0
        PREV_REQUEST_ID=""
        ALL_OK=true

        for chunk_txt in $CHUNK_FILES; do
            CHUNK_TEXT=$(cat "$chunk_txt")
            CHUNK_AUDIO="$CHUNK_DIR/audio_$(printf '%03d' $CHUNK_INDEX).mp3"

            PAYLOAD=$(python3 -c "
import json, sys
text = sys.stdin.read()
print(json.dumps({
    'text': text,
    'model_id': '$MODEL_ID',
    'voice_settings': {
        'stability': 0.4,
        'similarity_boost': 0.75,
        'style': 0.15,
        'speed': $SPEED_VAL
    }
}))
" <<< "$CHUNK_TEXT")

            HTTP_CODE=$(curl -s -o "$CHUNK_AUDIO" -w "%{http_code}" \
                -X POST "https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}?output_format=mp3_44100_128" \
                -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
                -H "Content-Type: application/json" \
                -d "$PAYLOAD" 2>/dev/null) || HTTP_CODE="000"

            if [ "$HTTP_CODE" != "200" ]; then
                log "ElevenLabs chunk $CHUNK_INDEX failed (HTTP $HTTP_CODE)"
                ALL_OK=false
                break
            fi
            CHUNK_INDEX=$((CHUNK_INDEX + 1))
        done

        if [ "$ALL_OK" = true ] && [ "$CHUNK_INDEX" -gt 0 ]; then
            # Concatenate MP3 chunks
            cat "$CHUNK_DIR"/audio_*.mp3 > "$AUDIO_FILE"
            log "Concatenated $CHUNK_INDEX chunks"
        else
            log "Chunked synthesis failed — falling back to macOS say"
            USE_ELEVENLABS=false
        fi
        rm -rf "$CHUNK_DIR"
    fi
fi

# ── Fallback to macOS say ─────────────────────────────────────────
if [ "$USE_ELEVENLABS" = false ]; then
    # Use clean_text.py for fallback since say doesn't understand audio tags
    FALLBACK_TEXT=$(echo "$RAW_TEXT" | python3 "$SCRIPTS_DIR/clean_text.py" 2>/dev/null) || FALLBACK_TEXT="$PROCESSED"
    AIFF_FILE="/tmp/cursor-tts-current.aiff"
    say -o "$AIFF_FILE" "$FALLBACK_TEXT" 2>/dev/null || die "macOS say failed"

    printf '%s' "$QUEUE_FILE" > "$PLAYBACK_FILE_REF"
    printf '%s' "$AIFF_FILE" > "$AUDIO_REF"
    afplay "$AIFF_FILE" &
    PLAY_PID=$!
    echo "$PLAY_PID" > "$PID_FILE"

    log "Playing via macOS say fallback (PID $PLAY_PID)"
    wait "$PLAY_PID" 2>/dev/null || true
    finish_playback_if_owner "$PLAY_PID" || true
    exit 0
fi

# ── Play via afplay ───────────────────────────────────────────────
log "Playing via ElevenLabs (voice=$VOICE_ID, model=$MODEL_ID, speed=${DEFAULT_SPEED}x, afplay_rate=${AFPLAY_RATE})"

printf '%s' "$QUEUE_FILE" > "$PLAYBACK_FILE_REF"
printf '%s' "$AUDIO_FILE" > "$AUDIO_REF"
afplay -r "$AFPLAY_RATE" "$AUDIO_FILE" &
PLAY_PID=$!
echo "$PLAY_PID" > "$PID_FILE"

log "Playback started (PID $PLAY_PID, file=$(basename "$QUEUE_FILE"))"

wait "$PLAY_PID" 2>/dev/null || true
finish_playback_if_owner "$PLAY_PID" || true
