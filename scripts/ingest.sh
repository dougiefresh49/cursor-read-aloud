#!/usr/bin/env bash
#
# ingest.sh — afterAgentResponse hook script
# Reads hook JSON payload from stdin and writes a queue file for later playback.
# Runs from ~/.cursor/ (user-level hook working directory).
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
QUEUE_DIR="$TTS_DIR/queue"
LOG_FILE="$TTS_DIR/logs/hook.log"

mkdir -p "$QUEUE_DIR" "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ingest: $*" >> "$LOG_FILE"; }

LISTENING_FLAG="$TTS_DIR/listening.enabled"
if [ -f "$LISTENING_FLAG" ]; then
    case "$(tr -d ' \n' < "$LISTENING_FLAG")" in
        0|false|FALSE|off)
            log "Listening paused — skipping queue"
            exit 0
            ;;
    esac
fi

input=$(cat)

text=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text',''))" 2>/dev/null) || {
    log "Failed to parse text from hook payload"
    exit 0
}

if [ -z "$text" ]; then
    log "Empty text in hook payload — skipping"
    exit 0
fi

conversation_id=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('conversation_id','unknown'))" 2>/dev/null) || conversation_id="unknown"
generation_id=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('generation_id',''))" 2>/dev/null) || generation_id=""
model=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('model',''))" 2>/dev/null) || model=""
workspace_roots=$(echo "$input" | python3 -c "import sys,json; r=json.load(sys.stdin).get('workspace_roots',[]); print(r[0] if r else '')" 2>/dev/null) || workspace_roots=""

epoch=$(date +%s)
short_conv=$(echo "$conversation_id" | cut -c1-12)
filename="${epoch}-${short_conv}.json"
filepath="$QUEUE_DIR/$filename"

python3 -c "
import json, sys, os, sqlite3, hashlib

text = sys.argv[1]
conversation_id = sys.argv[2]
generation_id = sys.argv[3]
model = sys.argv[4]
epoch = sys.argv[5]
filepath = sys.argv[6]
workspace_root = sys.argv[7]

thread_title = ''

# Look up thread title from Cursor's workspace state DB
# Cursor stores composer data in workspaceStorage/<hash>/state.vscdb
ws_storage = os.path.expanduser('~/Library/Application Support/Cursor/User/workspaceStorage')
if os.path.isdir(ws_storage):
    for ws_dir in os.listdir(ws_storage):
        ws_json = os.path.join(ws_storage, ws_dir, 'workspace.json')
        db_path = os.path.join(ws_storage, ws_dir, 'state.vscdb')
        if not os.path.isfile(ws_json) or not os.path.isfile(db_path):
            continue

        # Match workspace by folder path
        try:
            with open(ws_json) as f:
                ws_data = json.load(f)
            ws_folder = ws_data.get('folder', '')
            # workspace_root is a filesystem path, ws_folder is a file:// URI
            if workspace_root and workspace_root not in ws_folder:
                continue
        except Exception:
            continue

        try:
            conn = sqlite3.connect(db_path)
            cur = conn.cursor()
            cur.execute(\"SELECT value FROM ItemTable WHERE key = 'composer.composerData'\")
            row = cur.fetchone()
            conn.close()
            if row:
                composer_data = json.loads(row[0])
                for c in composer_data.get('allComposers', []):
                    if c.get('composerId') == conversation_id:
                        thread_title = c.get('name', '')
                        break
        except Exception:
            pass

        if thread_title:
            break

if len(thread_title) > 40:
    thread_title = thread_title[:37] + '...'

data = {
    'text': text,
    'conversation_id': conversation_id,
    'generation_id': generation_id,
    'model': model,
    'timestamp': epoch,
    'thread_title': thread_title,
    'spoken': False
}
with open(filepath, 'w') as f:
    json.dump(data, f, indent=2)
" "$text" "$conversation_id" "$generation_id" "$model" "$epoch" "$filepath" "$workspace_roots"

log "Queued response: $filename (conv=$short_conv, ${#text} chars)"

exit 0
