#!/usr/bin/env bash
#
# cursor-read-aloud.5s.sh — SwiftBar plugin for Cursor TTS playback.
# Filename convention: <name>.<refresh_interval>.<ext>
# Refreshes every 5 seconds.
#

TTS_DIR="$HOME/.cursor/tts"
QUEUE_DIR="$TTS_DIR/queue"
CONFIG="$TTS_DIR/config.json"
SCRIPTS_DIR="$TTS_DIR/scripts"
PID_FILE="$TTS_DIR/.playback-pid"
LISTENING_FLAG="$TTS_DIR/listening.enabled"

# ── Listening on/off (default: on if flag missing) ────────────────
LISTENING=1
if [ -f "$LISTENING_FLAG" ]; then
    case "$(tr -d ' \n' < "$LISTENING_FLAG")" in
        0|false|FALSE|off) LISTENING=0 ;;
    esac
fi

# ── Read config ───────────────────────────────────────────────────
DEFAULT_SPEED="1.25"
CURRENT_MODEL="en_US-libritts_r-medium"
if [ -f "$CONFIG" ]; then
    DEFAULT_SPEED=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('default_speed', 1.25))" 2>/dev/null || echo "1.25")
    CURRENT_MODEL=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('model', 'en_US-libritts_r-medium'))" 2>/dev/null || echo "en_US-libritts_r-medium")
fi

# ── Count unplayed items ──────────────────────────────────────────
QUEUE_COUNT=0
if [ -d "$QUEUE_DIR" ]; then
    QUEUE_COUNT=$(find "$QUEUE_DIR" -name '*.json' -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
fi

# ── Check if playing ──────────────────────────────────────────────
IS_PLAYING=false
if [ -f "$PID_FILE" ]; then
    PLAY_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$PLAY_PID" ] && kill -0 "$PLAY_PID" 2>/dev/null; then
        IS_PLAYING=true
    fi
fi

# ── Title bar ─────────────────────────────────────────────────────
if [ "$LISTENING" = 0 ]; then
    if [ "$IS_PLAYING" = true ]; then
        echo "⏸🔊"
    elif [ "$QUEUE_COUNT" -gt 0 ] 2>/dev/null; then
        echo "⏸ $QUEUE_COUNT"
    else
        echo "⏸"
    fi
elif [ "$IS_PLAYING" = true ]; then
    echo "🔊 ($QUEUE_COUNT)"
elif [ "$QUEUE_COUNT" -gt 0 ] 2>/dev/null; then
    echo "🔈 $QUEUE_COUNT"
else
    echo "🔇"
fi

echo "---"

# ── Start / Stop listening (ingest + Piper memory) ────────────────
if [ "$LISTENING" = 0 ]; then
    echo "▶ Start listening | bash=$SCRIPTS_DIR/set_listening.sh param1=on terminal=false refresh=true"
else
    echo "⏸ Stop listening | bash=$SCRIPTS_DIR/set_listening.sh param1=off terminal=false refresh=true"
fi
echo "---"

# ── Now Playing / Stop ────────────────────────────────────────────
if [ "$IS_PLAYING" = true ]; then
    echo "⏹ Stop Playback | bash=$SCRIPTS_DIR/stop.sh terminal=false refresh=true"
    echo "---"
fi

# ── Queue items ───────────────────────────────────────────────────
if [ "$QUEUE_COUNT" -gt 0 ] 2>/dev/null && [ "$QUEUE_COUNT" -ne 0 ]; then
    # List up to 10 most recent queue items (newest first)
    SHOWN=0
    for f in $(ls -t "$QUEUE_DIR"/*.json 2>/dev/null); do
        if [ "$SHOWN" -ge 10 ]; then
            break
        fi

        BASENAME=$(basename "$f")

        PREVIEW=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
    title = d.get('thread_title', '').strip()
    if not title:
        title = d.get('conversation_id', 'unknown')[:8]
    if len(title) > 20:
        title = title[:18] + '...'
    text = d.get('text', '')[:50].replace('\n', ' ').strip()
    chars = len(d.get('text', ''))
    est = int(chars / 15)
    mins = est // 60
    secs = est % 60
    dur = f'{mins}m{secs:02d}s' if mins > 0 else f'{secs}s'
    print(f'[{title}] {text}... (~{dur})')
except Exception:
    print(sys.argv[1])
" "$f" 2>/dev/null || echo "$BASENAME")

        echo "$PREVIEW | bash=$SCRIPTS_DIR/play.sh param1=$f terminal=false refresh=true"
        SHOWN=$((SHOWN + 1))
    done
else
    echo "No queued responses"
fi

echo "---"

# ── Speed submenu ─────────────────────────────────────────────────
echo "Speed: ${DEFAULT_SPEED}x"
SPEEDS=("0.75" "1.0" "1.25" "1.5" "2.0")
for spd in "${SPEEDS[@]}"; do
    if [ "$spd" = "$DEFAULT_SPEED" ]; then
        LABEL="✓ ${spd}x"
    else
        LABEL="  ${spd}x"
    fi
    echo "--$LABEL | bash=$SCRIPTS_DIR/set_speed.sh param1=$spd terminal=false refresh=true"
done

echo "---"

# ── Voice submenu ─────────────────────────────────────────────────
VOICE_IDS=(
    en_US-libritts_r-medium
    en_US-norman-medium
    en_GB-northern_english_male-medium
    en_US-ryan-high
)
VOICE_NAMES=(
    "LibriTTS R (US)"
    "Norman (US)"
    "Northern English (male)"
    "Ryan (US, high)"
)
VOICE_DISPLAY="$CURRENT_MODEL"
i=0
while [ "$i" -lt "${#VOICE_IDS[@]}" ]; do
    if [ "${VOICE_IDS[$i]}" = "$CURRENT_MODEL" ]; then
        VOICE_DISPLAY="${VOICE_NAMES[$i]}"
        break
    fi
    i=$((i + 1))
done

echo "Voice: ${VOICE_DISPLAY}"
i=0
while [ "$i" -lt "${#VOICE_IDS[@]}" ]; do
    vid="${VOICE_IDS[$i]}"
    vname="${VOICE_NAMES[$i]}"
    if [ "$vid" = "$CURRENT_MODEL" ]; then
        LABEL="✓ ${vname}"
    else
        LABEL="  ${vname}"
    fi
    echo "--${LABEL} | bash=$SCRIPTS_DIR/set_voice.sh param1=${vid} terminal=false refresh=true"
    i=$((i + 1))
done

echo "---"

# ── Utility actions ───────────────────────────────────────────────
if [ "$QUEUE_COUNT" -gt 0 ] 2>/dev/null && [ "$QUEUE_COUNT" -ne 0 ]; then
    echo "Clear Queue | bash=$SCRIPTS_DIR/clear_queue.sh terminal=false refresh=true"
fi

echo "Open Config | bash=/usr/bin/open param1=$CONFIG terminal=false"
echo "Open Logs | bash=/usr/bin/open param1=$TTS_DIR/logs/ terminal=false"
echo "---"
echo "Refresh | refresh=true"
