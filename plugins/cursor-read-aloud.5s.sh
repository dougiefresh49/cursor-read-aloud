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
PLAYBACK_FILE_REF="$TTS_DIR/.playback-file"
PAUSED_FLAG="$TTS_DIR/.playback-paused"

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
NOTIFICATIONS_ON=0
NOTIFICATION_SOUND="default"
if [ -f "$CONFIG" ]; then
    DEFAULT_SPEED=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('default_speed', 1.25))" 2>/dev/null || echo "1.25")
    CURRENT_MODEL=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('model', 'en_US-libritts_r-medium'))" 2>/dev/null || echo "en_US-libritts_r-medium")
    NOTIFICATIONS_ON=$(python3 -c "import json; print(1 if json.load(open('$CONFIG')).get('notifications_enabled') is True else 0)" 2>/dev/null || echo "0")
    NOTIFICATION_SOUND=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('notification_sound', 'default'))" 2>/dev/null || echo "default")
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

IS_PAUSED=false
if [ -f "$PAUSED_FLAG" ]; then
    IS_PAUSED=true
fi

# ── Menu bar image (SwiftBar: image= base64) ──────────────────────
ICON_DIR="$TTS_DIR/icons"
ICON_IDLE_MENU="$ICON_DIR/tmnt-menubar-idle.png"
ICON_QUEUE_MENU="$ICON_DIR/tmnt-menubar-queued.png"
ICON_IDLE_FALLBACK="$ICON_DIR/tmnt-icon.png"
ICON_QUEUE_FALLBACK="$ICON_DIR/tmnt-notification-queued.png"
CACHE_DIR="$TTS_DIR/cache"

swiftbar_image_b64() {
    local src="$1"
    local name cfile
    name=$(basename "$src")
    cfile="$CACHE_DIR/swiftbar-${name}.b64"
    [ -f "$src" ] || return 1
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
    if [ ! -f "$cfile" ] || [ "$src" -nt "$cfile" ]; then
        base64 <"$src" | tr -d '\n' >"$cfile"
    fi
    cat "$cfile"
}

BAR_SRC=""
if [ "$QUEUE_COUNT" -gt 0 ] 2>/dev/null; then
    BAR_SRC="$ICON_QUEUE_MENU"
    [ -f "$BAR_SRC" ] || BAR_SRC="$ICON_QUEUE_FALLBACK"
else
    BAR_SRC="$ICON_IDLE_MENU"
    [ -f "$BAR_SRC" ] || BAR_SRC="$ICON_IDLE_FALLBACK"
fi

BAR_B64=""
if [ -n "$BAR_SRC" ] && [ -f "$BAR_SRC" ]; then
    BAR_B64=$(swiftbar_image_b64 "$BAR_SRC") || BAR_B64=""
fi

# ── Title bar ─────────────────────────────────────────────────────
# SwiftBar often does not show badge= when the header is image-only; put the count in
# the title so it renders beside the icon (same as the old emoji + number layout).
if [ -n "$BAR_B64" ]; then
    if [ "$QUEUE_COUNT" -gt 0 ] 2>/dev/null; then
        echo "${QUEUE_COUNT} | image=${BAR_B64} dropdown=false"
    else
        echo " | image=${BAR_B64} dropdown=false"
    fi
elif [ "$LISTENING" = 0 ]; then
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

# ── Play latest (SwiftBar: ctrl+shift+p; Hammerspoon: ctrl+Play) ─
echo "Play Latest | bash=$SCRIPTS_DIR/play_latest.sh terminal=false refresh=true shortcut=ctrl+shift+p"

echo "---"

# ── Now playing (media controls) ──────────────────────────────────
if [ "$IS_PLAYING" = true ]; then
    if [ "$IS_PAUSED" = true ]; then
        echo "▶ Resume | bash=$SCRIPTS_DIR/pause.sh terminal=false refresh=true shortcut=ctrl+shift+space"
    else
        echo "⏯ Pause | bash=$SCRIPTS_DIR/pause.sh terminal=false refresh=true shortcut=ctrl+shift+space"
    fi
    echo "⏮ Start Over | bash=$SCRIPTS_DIR/restart.sh terminal=false refresh=true"
    echo "⏹ Stop Playback | bash=$SCRIPTS_DIR/stop.sh terminal=false refresh=true"
    if [ -f "$PLAYBACK_FILE_REF" ]; then
        NOW_LINE=$(python3 -c "
import json, sys
path = sys.argv[1]
try:
    with open(path) as fh:
        d = json.load(fh)
    title = (d.get('thread_title') or '').strip()
    if not title:
        title = str(d.get('conversation_id', 'unknown'))[:12]
    if len(title) > 28:
        title = title[:26] + '...'
    text = (d.get('text', '') or '')[:60].replace(chr(10), ' ').strip()
    print(f'Now Playing: {title} — {text}...')
except Exception:
    print('Now Playing: …')
" "$(tr -d '\n' < "$PLAYBACK_FILE_REF")" 2>/dev/null || echo "Now Playing: …")
        echo "$NOW_LINE | disabled=true size=11"
    fi
    echo "---"
fi

# ── Agent Messages ──────────────────────────────────────────────
echo "Agent Messages | disabled=true size=12"
export QUEUE_DIR SCRIPTS_DIR
if [ "$QUEUE_COUNT" -gt 0 ] 2>/dev/null && [ "$QUEUE_COUNT" -ne 0 ]; then
    python3 - <<'PY'
import base64
import json
import os
from collections import defaultdict

queue_dir = os.environ["QUEUE_DIR"]
scripts_dir = os.environ["SCRIPTS_DIR"]

def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None

def preview_for(path, data):
    title = (data.get("thread_title") or "").strip()
    if not title:
        cid = data.get("conversation_id") or "unknown"
        title = str(cid)[:12]
    if len(title) > 22:
        title = title[:20] + "..."
    text = (data.get("text") or "")[:50].replace("\n", " ").strip()
    chars = len(data.get("text") or "")
    est = int(chars / 15)
    mins, secs = divmod(est, 60)
    dur = f"{mins}m{secs:02d}s" if mins > 0 else f"{secs}s"
    return f"[{title}] {text}... (~{dur})"

paths = []
try:
    for name in os.listdir(queue_dir):
        if name.endswith(".json"):
            paths.append(os.path.join(queue_dir, name))
except OSError:
    paths = []

# Newest file first (epoch prefix in filename)
paths.sort(key=lambda p: os.path.basename(p), reverse=True)

groups = defaultdict(list)
for p in paths:
    d = load_json(p)
    if not d:
        continue
    cid = (d.get("conversation_id") or "").strip()
    key = cid if cid else (d.get("thread_title") or "unknown")
    groups[key].append((p, d))

# Sort groups by newest message (max basename / path order)
def group_sort_key(items):
    return max((os.path.basename(i[0]) for i in items), default="")

group_list = sorted(groups.items(), key=lambda kv: group_sort_key(kv[1]), reverse=True)

for grp_key, items in group_list:
    items.sort(key=lambda x: os.path.basename(x[0]), reverse=True)
    first = items[0][1]
    label = (first.get("thread_title") or "").strip()
    if not label:
        label = str(first.get("conversation_id") or "Chat")[:16]
    if len(label) > 32:
        label = label[:30] + "..."
    n = len(items)
    # Zero-padded width so counts read cleanly: (01) … (02) … (15) …
    count_prefix = f"({n:02d}) "
    print(f"{count_prefix}{label} | disabled=true")
    for path, data in items:
        prev = preview_for(path, data)
        # SwiftBar: escape pipe in menu text? rare in previews
        prev = prev.replace("|", "/")
        print(
            f"--{prev} | bash={scripts_dir}/play.sh param1={path} terminal=false refresh=true"
        )
    token = base64.urlsafe_b64encode(
        json.dumps({"key": grp_key}, separators=(",", ":")).encode("utf-8")
    ).decode("ascii").rstrip("=")
    print("-- | disabled=true")
    print(
        f"--Clear Messages | bash={scripts_dir}/clear_thread_queue.sh param1={token} terminal=false refresh=true"
    )
PY
else
    echo "No queued responses | disabled=true"
fi

echo "---"

# ── Settings (voice, speed, notifications) ────────────────────────
echo "Settings | disabled=true size=12"

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

if [ "$NOTIFICATIONS_ON" = 1 ]; then
    echo "Notifications: On | bash=$SCRIPTS_DIR/set_notifications.sh param1=off terminal=false refresh=true"
else
    echo "Notifications: Off | bash=$SCRIPTS_DIR/set_notifications.sh param1=on terminal=false refresh=true"
fi

echo "Notification sound: ${NOTIFICATION_SOUND}"
export NOTIFICATION_SOUND_MENU_SCRIPTS="$SCRIPTS_DIR"
export NOTIFICATION_SOUND_MENU_CURRENT="$NOTIFICATION_SOUND"
python3 - <<'PY'
"""One submenu: built-in alert names, optional '---' row, then ~/Library/Sounds (cheap: one readdir per refresh)."""
import base64
import os

scripts = os.environ["NOTIFICATION_SOUND_MENU_SCRIPTS"]
current = os.environ.get("NOTIFICATION_SOUND_MENU_CURRENT", "default").strip()

builtins = [
    ("default", "Default"),
    ("Glass", "Glass"),
    ("Ping", "Ping"),
    ("Tink", "Tink"),
    ("Pop", "Pop"),
    ("Submarine", "Submarine"),
    ("Purr", "Purr"),
    ("Funk", "Funk"),
    ("Hero", "Hero"),
    ("Basso", "Basso"),
    ("Blow", "Blow"),
    ("Bottle", "Bottle"),
    ("Frog", "Frog"),
    ("Morse", "Morse"),
    ("Sosumi", "Sosumi"),
]

def selected(sid: str) -> bool:
    if sid == "default":
        return current.lower() == "default"
    return sid == current or sid.lower() == current.lower()


def enc(s: str) -> str:
    return "B64:" + base64.urlsafe_b64encode(s.encode("utf-8")).decode("ascii").rstrip("=")


builtins_lower = {sid.lower() for sid, _ in builtins}
for sid, slab in builtins:
    mark = "✓ " if selected(sid) else "  "
    print(
        f"--{mark}{slab} | bash={scripts}/set_notification_sound.sh param1={sid} terminal=false refresh=true"
    )

custom_dir = os.path.join(os.path.expanduser("~"), "Library", "Sounds")
exts = {".aiff", ".aif", ".wav", ".caf", ".m4a"}
items = []
if os.path.isdir(custom_dir):
    try:
        for fn in sorted(os.listdir(custom_dir)):
            path = os.path.join(custom_dir, fn)
            if not os.path.isfile(path):
                continue
            stem, ext = os.path.splitext(fn)
            if ext.lower() not in exts:
                continue
            if stem.lower() in builtins_lower:
                continue
            items.append(stem)
    except OSError:
        pass

if items:
    # Submenu row titled exactly "---" (leading "--" is SwiftBar submenu marker + "---")
    print("----- | disabled=true size=11")
    cur_lower = current.lower()
    for stem in items:
        is_cur = stem == current or stem.lower() == cur_lower
        mark = "✓ " if is_cur else "  "
        display = stem.replace("|", "—")
        print(
            f"--{mark}{display} | bash={scripts}/set_notification_sound.sh param1={enc(stem)} terminal=false refresh=true"
        )
PY

echo "---"

# ── Debug / Logs ────────────────────────────────────────────────
echo "Debug / Logs | disabled=true size=12"
echo "Open Config | bash=/usr/bin/open param1=$CONFIG terminal=false"
echo "Open Logs | bash=/usr/bin/open param1=$TTS_DIR/logs/ terminal=false"

echo "---"

echo "Refresh | refresh=true"
if [ "$QUEUE_COUNT" -gt 0 ] 2>/dev/null && [ "$QUEUE_COUNT" -ne 0 ]; then
    echo "Clear All Messages | bash=$SCRIPTS_DIR/clear_queue.sh terminal=false refresh=true"
fi

if [ "$LISTENING" = 0 ]; then
    echo "▶ Start listening | bash=$SCRIPTS_DIR/set_listening.sh param1=on terminal=false refresh=true"
else
    echo "⏸ Stop listening | bash=$SCRIPTS_DIR/set_listening.sh param1=off terminal=false refresh=true"
fi

echo "Quit | bash=$SCRIPTS_DIR/quit.sh terminal=false refresh=true"
