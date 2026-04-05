#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Read Aloud: Enqueue Text
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ✏️
# @raycast.argument1 { "type": "text", "placeholder": "Text to read (short snippet)" }
# @raycast.argument2 { "type": "text", "placeholder": "Thread title (optional)", "optional": true }

# Documentation:
# @raycast.description Pipes the first argument into the read-aloud queue. Best for short reminders; for long assistant replies use Enqueue Clipboard instead.
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

text="${1:-}"
title="${2:-Manual enqueue}"

if [ -z "$text" ]; then
  echo "Enter some text to enqueue."
  exit 1
fi

if ! printf '%s' "$text" | "$ENQUEUE" "$title"; then
  echo "Enqueue failed."
  exit 1
fi

echo "Queued text for read aloud."
