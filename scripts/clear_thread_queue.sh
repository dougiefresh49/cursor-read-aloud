#!/usr/bin/env bash
#
# clear_thread_queue.sh — Move queued JSON files for one thread to played/.
# Argument: urlsafe base64 JSON {"key":"<group key>"} where key matches
#   (conversation_id if set) else (thread_title or "unknown"), same as the SwiftBar plugin.
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
QUEUE_DIR="$TTS_DIR/queue"
PLAYED_DIR="$TTS_DIR/played"
LOG_FILE="$TTS_DIR/logs/hook.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] clear_thread_queue: $*" >> "$LOG_FILE" 2>/dev/null || true; }

TOKEN="${1:-}"
if [ -z "$TOKEN" ]; then
    echo "Usage: $0 <base64url-json-token>" >&2
    exit 1
fi

mkdir -p "$PLAYED_DIR" "$(dirname "$LOG_FILE")"

COUNT=$(python3 - "$TOKEN" "$QUEUE_DIR" "$PLAYED_DIR" <<'PY'
import base64, json, os, shutil, sys

token = sys.argv[1]
queue_dir = sys.argv[2]
played_dir = sys.argv[3]

pad = "=" * (-len(token) % 4)
try:
    raw = base64.urlsafe_b64decode(token + pad)
    payload = json.loads(raw.decode("utf-8"))
except (ValueError, json.JSONDecodeError, UnicodeDecodeError):
    sys.exit(2)

key = payload.get("key")
if key is None or key == "":
    sys.exit(2)

# Must match plugins/cursor-read-aloud.5s.sh grouping exactly.
def group_key_of(d):
    cid = (d.get("conversation_id") or "").strip()
    if cid:
        return cid
    return d.get("thread_title") or "unknown"


n = 0
try:
    names = [x for x in os.listdir(queue_dir) if x.endswith(".json")]
except OSError:
    names = []

for name in names:
    path = os.path.join(queue_dir, name)
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, json.JSONDecodeError):
        continue
    if group_key_of(d) != key:
        continue
    shutil.move(path, os.path.join(played_dir, name))
    n += 1

print(n)
PY
) || exit 1

log "Moved $COUNT file(s) for thread key (hashed in token)"
exit 0
