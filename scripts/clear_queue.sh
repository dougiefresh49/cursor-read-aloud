#!/usr/bin/env bash
#
# clear_queue.sh — Move all queued responses to played/.
#
set -euo pipefail

TTS_DIR="$HOME/.cursor/tts"
QUEUE_DIR="$TTS_DIR/queue"
PLAYED_DIR="$TTS_DIR/played"

mkdir -p "$PLAYED_DIR"

COUNT=0
for f in "$QUEUE_DIR"/*.json; do
    [ -f "$f" ] || continue
    mv "$f" "$PLAYED_DIR/"
    COUNT=$((COUNT + 1))
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] clear_queue: Moved $COUNT files" >> "$TTS_DIR/logs/hook.log" 2>/dev/null
