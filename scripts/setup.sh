#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TTS_DIR="$HOME/.cursor/tts"
HOOKS_DIR="$HOME/.cursor"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
SWIFTBAR_PLUGINS_DIR="${SWIFTBAR_PLUGINS_DIR:-$HOME/projects/Swiftbar/Plugins}"
PIPER_PORT=5111

log() { echo "[setup] $*"; }
err() { echo "[setup] ERROR: $*" >&2; }

# ── 1. Create directory structure ──────────────────────────────────
log "Creating directory structure under $TTS_DIR"
mkdir -p "$TTS_DIR"/{models,queue,played,cache,scripts,logs}

# ── 2. Install piper-tts ──────────────────────────────────────────
if python3 -c "import piper" 2>/dev/null; then
    log "piper-tts already installed"
else
    log "Installing piper-tts..."
    pip3 install piper-tts
fi

if python3 -c "import flask" 2>/dev/null; then
    log "flask already installed (needed for Piper HTTP server)"
else
    log "Installing flask (required by Piper HTTP server)..."
    pip3 install 'piper-tts[http]'
fi

# ── 3. Download voice model ───────────────────────────────────────
MODEL_FILE="$TTS_DIR/models/en_US-libritts_r-medium.onnx"
MODEL_JSON="$TTS_DIR/models/en_US-libritts_r-medium.onnx.json"
HF_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium"

if [ -f "$MODEL_FILE" ] && [ -f "$MODEL_JSON" ]; then
    log "Voice model already downloaded"
else
    log "Downloading en_US-libritts_r-medium voice model..."
    if python3 -m piper.download_voices en_US-libritts_r-medium --data-dir "$TTS_DIR/models" 2>/dev/null; then
        log "Downloaded via piper.download_voices"
    else
        log "piper.download_voices failed (likely SSL issue) — downloading via curl"
        curl -L -o "$MODEL_FILE" "$HF_BASE/en_US-libritts_r-medium.onnx" || {
            err "Failed to download model ONNX file"; exit 1;
        }
        curl -L -o "$MODEL_JSON" "$HF_BASE/en_US-libritts_r-medium.onnx.json" || {
            err "Failed to download model config JSON"; exit 1;
        }
        log "Downloaded via curl fallback"
    fi
fi

# ── 4. Copy scripts ───────────────────────────────────────────────
log "Installing scripts to $TTS_DIR/scripts/"
cp "$PROJECT_DIR/scripts/ingest.sh"     "$TTS_DIR/scripts/ingest.sh"
cp "$PROJECT_DIR/scripts/play.sh"       "$TTS_DIR/scripts/play.sh"
cp "$PROJECT_DIR/scripts/stop.sh"       "$TTS_DIR/scripts/stop.sh"
cp "$PROJECT_DIR/scripts/set_speed.sh"   "$TTS_DIR/scripts/set_speed.sh"
cp "$PROJECT_DIR/scripts/clear_queue.sh" "$TTS_DIR/scripts/clear_queue.sh"
cp "$PROJECT_DIR/scripts/set_listening.sh" "$TTS_DIR/scripts/set_listening.sh"
cp "$PROJECT_DIR/scripts/enqueue_manual.sh" "$TTS_DIR/scripts/enqueue_manual.sh"
cp "$PROJECT_DIR/scripts/clean_text.py"  "$TTS_DIR/scripts/clean_text.py"
chmod +x "$TTS_DIR/scripts/"*.sh

# ── 5. Write default config (if not present) ──────────────────────
CONFIG_FILE="$TTS_DIR/config.json"
if [ -f "$CONFIG_FILE" ]; then
    log "Config already exists at $CONFIG_FILE — skipping"
else
    log "Writing default config to $CONFIG_FILE"
    cp "$PROJECT_DIR/config/config.json" "$CONFIG_FILE"
fi

# ── 6. Install hooks.json ─────────────────────────────────────────
HOOKS_FILE="$HOOKS_DIR/hooks.json"
if [ -f "$HOOKS_FILE" ]; then
    if grep -q "afterAgentResponse" "$HOOKS_FILE" 2>/dev/null; then
        log "afterAgentResponse hook already registered in $HOOKS_FILE"
    else
        err "$HOOKS_FILE exists but does not contain afterAgentResponse hook."
        err "Please merge manually from: $PROJECT_DIR/config/hooks.json"
    fi
else
    log "Installing hooks.json to $HOOKS_FILE"
    cp "$PROJECT_DIR/config/hooks.json" "$HOOKS_FILE"
fi

# ── 7. Install LaunchAgent ─────────────────────────────────────────
PLIST_NAME="com.local.piper-tts-server.plist"
PLIST_DEST="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
PYTHON3_PATH="$(which python3)"
mkdir -p "$LAUNCH_AGENTS_DIR"

log "Generating LaunchAgent plist (python3=$PYTHON3_PATH, home=$HOME)"
sed -e "s|__HOME__|$HOME|g" -e "s|__PYTHON3__|$PYTHON3_PATH|g" \
    "$PROJECT_DIR/config/$PLIST_NAME.template" > "$PLIST_DEST"

# Load/reload the agent
PLIST_LABEL="com.local.piper-tts-server"
if launchctl list "$PLIST_LABEL" &>/dev/null; then
    log "Reloading LaunchAgent..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi
launchctl load "$PLIST_DEST"
log "Piper HTTP server LaunchAgent loaded"

# ── 8. Install SwiftBar plugin ─────────────────────────────────────
if [ -d "$SWIFTBAR_PLUGINS_DIR" ]; then
    log "Installing SwiftBar plugin to $SWIFTBAR_PLUGINS_DIR"
    cp "$PROJECT_DIR/plugins/cursor-read-aloud.5s.sh" "$SWIFTBAR_PLUGINS_DIR/"
    chmod +x "$SWIFTBAR_PLUGINS_DIR/cursor-read-aloud.5s.sh"
else
    log "SwiftBar plugin directory not found at $SWIFTBAR_PLUGINS_DIR"
    log "Install SwiftBar (brew install --cask swiftbar) then re-run setup,"
    log "or manually copy plugins/cursor-read-aloud.5s.sh to your SwiftBar plugins folder."
fi

# ── 9. Verify Piper HTTP server ───────────────────────────────────
log "Waiting for Piper HTTP server to start..."
MAX_WAIT=15
WAITED=0
while ! curl -s "localhost:$PIPER_PORT/voices" >/dev/null 2>&1; do
    sleep 1
    WAITED=$((WAITED + 1))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        err "Piper HTTP server did not start within ${MAX_WAIT}s"
        err "Check logs at: $TTS_DIR/logs/piper-server.log"
        err "Try running manually: python3 -m piper.http_server -m en_US-libritts_r-medium --data-dir $TTS_DIR/models --port $PIPER_PORT"
        exit 1
    fi
done
log "Piper HTTP server is running on port $PIPER_PORT"

log ""
log "Setup complete! Summary:"
log "  Config:      $CONFIG_FILE"
log "  Scripts:     $TTS_DIR/scripts/"
log "  Queue:       $TTS_DIR/queue/"
log "  Hooks:       $HOOKS_FILE"
log "  LaunchAgent: $PLIST_DEST"
log "  Piper:       http://localhost:$PIPER_PORT"
log ""
log "Try: echo 'Hello world' | python3 $TTS_DIR/scripts/clean_text.py"
