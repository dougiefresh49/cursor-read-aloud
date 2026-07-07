#!/usr/bin/env bash
#
# load_env.sh — Source API keys from .env file.
# Checks ~/.cursor/tts/.env first, then the project root.
#
# Usage: source "$SCRIPTS_DIR/load_env.sh"
#

_load_env_file() {
    local envfile="$1"
    if [ -f "$envfile" ]; then
        while IFS='=' read -r key value; do
            key=$(echo "$key" | tr -d ' ')
            [[ -z "$key" || "$key" == \#* ]] && continue
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            export "$key=$value"
        done < "$envfile"
        return 0
    fi
    return 1
}

if [ -z "${ELEVENLABS_API_KEY:-}" ] || [ -z "${GEMINI_API_KEY:-}" ]; then
    _load_env_file "$HOME/.cursor/tts/.env" || \
    _load_env_file "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/.env" || \
    true
fi
