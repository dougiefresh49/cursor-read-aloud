#!/usr/bin/env bash
#
# piper_http_launch.sh — Start Piper HTTP server using model/port from config.json.
# Invoked by LaunchAgent; uses exec so Piper replaces this shell as PID 1 of the job.
#
set -euo pipefail

TTS_DIR="${HOME}/.cursor/tts"
CONFIG="${TTS_DIR}/config.json"

_cfg=$(python3 <<'PY'
import json, os

path = os.path.expanduser("~/.cursor/tts/config.json")
defaults = {"model": "en_US-libritts_r-medium", "piper_port": 5111}
try:
    with open(path, encoding="utf-8") as f:
        c = json.load(f)
except (OSError, json.JSONDecodeError):
    c = {}
model = c.get("model", defaults["model"])
port = int(c.get("piper_port", defaults["piper_port"]))
print(model)
print(port)
PY
)

MODEL=$(printf '%s\n' "$_cfg" | sed -n '1p')
PORT=$(printf '%s\n' "$_cfg" | sed -n '2p')

exec python3 -m piper.http_server -m "$MODEL" --data-dir "${TTS_DIR}/models" --port "$PORT"
