#!/usr/bin/env bash
#
# set_voice.sh — Set Piper voice (model id) in config.json and restart the server if running.
#
# Usage: set_voice.sh <model-id>
#   e.g. set_voice.sh en_US-ryan-high
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
CONFIG="$TTS_DIR/config.json"
MODELS="$TTS_DIR/models"
PLIST="$HOME/Library/LaunchAgents/com.local.piper-tts-server.plist"
LABEL="com.local.piper-tts-server"
LOG_FILE="$TTS_DIR/logs/hook.log"

LIBRI="en_US-libritts_r-medium"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] set_voice: $*" >> "$LOG_FILE" 2>/dev/null || true; }

mkdir -p "$TTS_DIR" "$(dirname "$LOG_FILE")"

MODEL="${1:-}"
if [ -z "$MODEL" ]; then
  echo "Usage: $0 <model-id>" >&2
  exit 1
fi

ONNX="$MODELS/${MODEL}.onnx"
JSONF="$MODELS/${MODEL}.onnx.json"
if [ ! -f "$ONNX" ] || [ ! -f "$JSONF" ]; then
  log "Missing model files for $MODEL (need .onnx and .onnx.json in $MODELS)"
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  echo '{}' > "$CONFIG"
fi

python3 - "$MODEL" "$LIBRI" "$CONFIG" <<'PY'
import json, sys

model, libri, path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(path, encoding="utf-8") as f:
    config = json.load(f)

config["model"] = model
if model != libri:
    config["speaker_id"] = 0

with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY

log "Set model to $MODEL"

restart_piper() {
  if [ ! -f "$PLIST" ]; then
    log "No LaunchAgent plist at $PLIST — not restarting"
    return 0
  fi
  if ! launchctl list 2>/dev/null | grep -q "$LABEL"; then
    log "Piper LaunchAgent not loaded — config updated for next start"
    return 0
  fi
  if launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null; then
    log "Piper restarted (kickstart)"
    return 0
  fi
  log "kickstart failed — trying unload/load"
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST" 2>/dev/null || log "launchctl load failed"
}

restart_piper
