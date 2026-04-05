#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Read Aloud: Enqueue File
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 📄
# @raycast.argument1 { "type": "text", "placeholder": "Path to text or markdown file" }
# @raycast.argument2 { "type": "text", "placeholder": "Thread title (optional)", "optional": true }

# Documentation:
# @raycast.description Reads a file and queues its contents for Cursor Read Aloud. Paste a full path (e.g. from Finder: Get Info, or drag file into Terminal).
# @raycast.packageName Cursor Read Aloud
# @raycast.needsConfirmation false
# @raycast.author dougiefresh49
# @raycast.authorURL https://github.com/dougiefresh49

set -euo pipefail

ENQUEUE="${HOME}/.cursor/tts/scripts/enqueue_manual.sh"
if [ ! -x "$ENQUEUE" ]; then
  echo "Missing or not executable: $ENQUEUE — run scripts/setup.sh first."
  exit 1
fi

file_path="${1:-}"
title="${2:-Manual enqueue}"

if [ -z "$file_path" ]; then
  echo "Enter a file path."
  exit 1
fi

# Expand ~ and strip quotes from Finder drag-and-drop
file_path="${file_path/#\~/$HOME}"
file_path="${file_path//\"/}"

if [ ! -f "$file_path" ]; then
  echo "File not found: $file_path"
  exit 1
fi

if ! "$ENQUEUE" "$title" < "$file_path"; then
  echo "Enqueue failed."
  exit 1
fi

echo "Queued: $file_path"
