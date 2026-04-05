#!/usr/bin/env bash
#
# notify_queued.sh — macOS notification after a queue file is written (if enabled in config).
#
# Prefers a locally-built terminal-notifier at /Applications/terminal-notifier.app (click-to-play).
# Falls back to osascript (banner + sound, no click action).
#
# Usage: notify_queued.sh /absolute/path/to/queue/file.json
#
set -u

filepath="${1:-}"
if [ -z "$filepath" ] || [ ! -f "$filepath" ]; then
  exit 0
fi

TTS_DIR="${HOME}/.cursor/tts"
CONFIG="${TTS_DIR}/config.json"
LOG_FILE="${TTS_DIR}/logs/hook.log"

logn() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] notify: $*" >>"$LOG_FILE" 2>/dev/null || true
}

enabled=$(python3 - "$CONFIG" <<'PY'
import json, sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        c = json.load(f)
    print("1" if c.get("notifications_enabled") is True else "0")
except (OSError, json.JSONDecodeError, TypeError):
    print("0")
PY
)

if [ "$enabled" != "1" ]; then
  exit 0
fi

logn "preparing notification for $(basename "$filepath")"

python3 - "$filepath" "$CONFIG" "$LOG_FILE" <<'PY'
import json
import os
import shlex
import shutil
import subprocess
import sys
from datetime import datetime

filepath, config_path, log_path = sys.argv[1], sys.argv[2], sys.argv[3]

TTS_DIR = os.path.expanduser("~/.cursor/tts")
PLAY = os.path.join(TTS_DIR, "scripts", "play.sh")


def log(msg: str) -> None:
    try:
        with open(log_path, "a", encoding="utf-8") as fh:
            ts = datetime.now().strftime("[%Y-%m-%d %H:%M:%S] ")
            fh.write(ts + "notify: " + msg + "\n")
    except OSError:
        pass


# ── Load config ──────────────────────────────────────────────────
try:
    with open(config_path, encoding="utf-8") as f:
        config = json.load(f)
except (OSError, json.JSONDecodeError):
    config = {}

# ── Load queue item ──────────────────────────────────────────────
try:
    with open(filepath, encoding="utf-8") as f:
        d = json.load(f)
except (OSError, json.JSONDecodeError):
    d = {}

# ── Clean text for preview ───────────────────────────────────────
scripts_dir = os.path.join(TTS_DIR, "scripts")
if scripts_dir not in sys.path:
    sys.path.insert(0, scripts_dir)

try:
    from clean_text import clean
except ImportError:
    clean = None

tt = (d.get("thread_title") or "").strip().replace("\n", " ") or "Queued message"
raw = (d.get("text") or "").strip()
if raw and clean is not None:
    try:
        preview = clean(raw)
    except Exception:
        preview = raw
else:
    preview = raw

preview = preview.replace("\n", " ").strip()
if len(preview) > 150:
    preview = preview[:147] + "..."
if not preview:
    preview = "New reply queued."
if len(tt) > 60:
    tt = tt[:57] + "..."


# ── Notification icon (optional config key) ──────────────────────
icon_path = config.get("notification_icon", "")
icon_url = ""
if icon_path:
    expanded = os.path.expanduser(icon_path)
    if os.path.isfile(expanded):
        icon_url = "file://" + expanded


# ── Try terminal-notifier (rebuilt in /Applications) ─────────────
TN_APP = "/Applications/terminal-notifier.app/Contents/MacOS/terminal-notifier"
tn_bin = None
if os.path.isfile(TN_APP) and os.access(TN_APP, os.X_OK):
    tn_bin = TN_APP
else:
    found = shutil.which("terminal-notifier")
    if found:
        tn_bin = found

if tn_bin:
    execute = shlex.quote(PLAY) + " " + shlex.quote(filepath)
    nid = os.path.splitext(os.path.basename(filepath))[0]

    cmd = [
        tn_bin,
        "-group", nid,
        "-sound", "default",
        "-ignoreDnD",
        "-title", "Cursor Read Aloud",
        "-subtitle", tt,
        "-message", preview,
        "-execute", execute,
    ]
    if icon_url:
        cmd += ["-appIcon", icon_url]

    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode == 0:
        log(f"terminal-notifier ok {os.path.basename(filepath)}")
    else:
        err = (r.stderr or r.stdout or "").strip()
        log(f"terminal-notifier exit {r.returncode}: {err}; falling back to osascript")
        tn_bin = None  # trigger fallback below
    if r.stderr and r.stderr.strip():
        log(f"terminal-notifier stderr: {r.stderr.strip()}")

# ── Fallback: osascript ──────────────────────────────────────────
if not tn_bin:
    def esc(s: str) -> str:
        return s.replace("\\", "\\\\").replace('"', '\\"')

    script = (
        f'display notification "{esc(preview)}" '
        f'with title "Cursor Read Aloud" '
        f'subtitle "{esc(tt)}" '
        f'sound name "Glass"'
    )
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if r.returncode == 0:
        log(f"notification sent (osascript) {os.path.basename(filepath)}")
    else:
        err = (r.stderr or r.stdout or "").strip()
        log(f"osascript failed (exit {r.returncode}): {err}")
PY

exit 0
