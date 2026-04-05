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
mkdir -p "$TTS_DIR"/{models,queue,played,cache,scripts,logs,icons}

# ── 1b. Menu bar + notification icons ─────────────────────────────
ICON_SRC_DIR="$PROJECT_DIR/icons"
ICON_DST_DIR="$TTS_DIR/icons"
if [ -d "$ICON_SRC_DIR" ] && [ -f "$ICON_SRC_DIR/tmnt-icon.png" ] && [ -f "$ICON_SRC_DIR/tmnt-notification-queued.png" ]; then
    log "Installing icons to $ICON_DST_DIR"
    cp -f "$ICON_SRC_DIR/tmnt-icon.png" "$ICON_DST_DIR/tmnt-icon.png"
    cp -f "$ICON_SRC_DIR/tmnt-notification-queued.png" "$ICON_DST_DIR/tmnt-notification-queued.png"
    # Downscale for SwiftBar (base64 header); keeps full-size copies for notifications
    if command -v sips >/dev/null 2>&1; then
        sips -Z 36 "$ICON_DST_DIR/tmnt-icon.png" --out "$ICON_DST_DIR/tmnt-menubar-idle.png" >/dev/null 2>&1 \
            || cp -f "$ICON_DST_DIR/tmnt-icon.png" "$ICON_DST_DIR/tmnt-menubar-idle.png"
        sips -Z 36 "$ICON_DST_DIR/tmnt-notification-queued.png" --out "$ICON_DST_DIR/tmnt-menubar-queued.png" >/dev/null 2>&1 \
            || cp -f "$ICON_DST_DIR/tmnt-notification-queued.png" "$ICON_DST_DIR/tmnt-menubar-queued.png"
    else
        cp -f "$ICON_DST_DIR/tmnt-icon.png" "$ICON_DST_DIR/tmnt-menubar-idle.png"
        cp -f "$ICON_DST_DIR/tmnt-notification-queued.png" "$ICON_DST_DIR/tmnt-menubar-queued.png"
    fi
else
    log "Optional repo icons missing under $ICON_SRC_DIR (SwiftBar uses emoji fallback)"
fi

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

# ── 3b. Optional Piper voices (skip if already present) ──────────
download_voice_pair() {
    local vid="$1" base="$2"
    local onnx="$TTS_DIR/models/${vid}.onnx"
    local jsn="$TTS_DIR/models/${vid}.onnx.json"
    if [ -f "$onnx" ] && [ -f "$jsn" ]; then
        log "Voice $vid already downloaded"
        return 0
    fi
    log "Downloading $vid..."
    curl -L -f -o "$onnx" "${base}/${vid}.onnx" || {
        err "Failed to download ${vid}.onnx"; return 1
    }
    curl -L -f -o "$jsn" "${base}/${vid}.onnx.json" || {
        err "Failed to download ${vid}.onnx.json"; return 1
    }
    log "Downloaded $vid"
}

download_voice_pair "en_US-norman-medium" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/norman/medium" || true
download_voice_pair "en_GB-northern_english_male-medium" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/northern_english_male/medium" || true
download_voice_pair "en_US-ryan-high" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high" || true

# ── 4. Copy scripts ───────────────────────────────────────────────
log "Installing scripts to $TTS_DIR/scripts/"
cp "$PROJECT_DIR/scripts/ingest.sh"     "$TTS_DIR/scripts/ingest.sh"
cp "$PROJECT_DIR/scripts/play.sh"       "$TTS_DIR/scripts/play.sh"
cp "$PROJECT_DIR/scripts/stop.sh"       "$TTS_DIR/scripts/stop.sh"
cp "$PROJECT_DIR/scripts/pause.sh"      "$TTS_DIR/scripts/pause.sh"
cp "$PROJECT_DIR/scripts/restart.sh"    "$TTS_DIR/scripts/restart.sh"
cp "$PROJECT_DIR/scripts/quit.sh"       "$TTS_DIR/scripts/quit.sh"
cp "$PROJECT_DIR/scripts/set_speed.sh"   "$TTS_DIR/scripts/set_speed.sh"
cp "$PROJECT_DIR/scripts/clear_queue.sh" "$TTS_DIR/scripts/clear_queue.sh"
cp "$PROJECT_DIR/scripts/clear_thread_queue.sh" "$TTS_DIR/scripts/clear_thread_queue.sh"
cp "$PROJECT_DIR/scripts/set_listening.sh" "$TTS_DIR/scripts/set_listening.sh"
cp "$PROJECT_DIR/scripts/enqueue_manual.sh" "$TTS_DIR/scripts/enqueue_manual.sh"
cp "$PROJECT_DIR/scripts/piper_http_launch.sh" "$TTS_DIR/scripts/piper_http_launch.sh"
cp "$PROJECT_DIR/scripts/set_voice.sh" "$TTS_DIR/scripts/set_voice.sh"
cp "$PROJECT_DIR/scripts/notify_queued.sh" "$TTS_DIR/scripts/notify_queued.sh"
cp "$PROJECT_DIR/scripts/set_notifications.sh" "$TTS_DIR/scripts/set_notifications.sh"
cp "$PROJECT_DIR/scripts/clean_text.py"  "$TTS_DIR/scripts/clean_text.py"
cp "$PROJECT_DIR/scripts/build_read_aloud_notifier_app.sh" "$TTS_DIR/scripts/build_read_aloud_notifier_app.sh"
chmod +x "$TTS_DIR/scripts/"*.sh

# ── 5. Write default config (if not present) ──────────────────────
CONFIG_FILE="$TTS_DIR/config.json"
if [ -f "$CONFIG_FILE" ]; then
    log "Config already exists at $CONFIG_FILE — skipping"
else
    log "Writing default config to $CONFIG_FILE"
    cp "$PROJECT_DIR/config/config.json" "$CONFIG_FILE"
fi

python3 - <<'PY'
import json
import os

p = os.path.join(os.path.expanduser("~"), ".cursor", "tts", "config.json")
try:
    with open(p, encoding="utf-8") as f:
        c = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(0)

changed = False
if "notifications_enabled" not in c:
    c["notifications_enabled"] = False
    changed = True
if "notification_icon" not in c:
    c["notification_icon"] = "~/.cursor/tts/icons/tmnt-notification-queued.png"
    changed = True
elif c.get("notification_icon") == "~/.cursor/tts/icons/tmnt-icon.png":
    c["notification_icon"] = "~/.cursor/tts/icons/tmnt-notification-queued.png"
    changed = True
if "terminal_notifier_app" not in c:
    c["terminal_notifier_app"] = ""
    changed = True
if changed:
    with open(p, "w", encoding="utf-8") as f:
        json.dump(c, f, indent=2)
        f.write("\n")
PY

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
mkdir -p "$LAUNCH_AGENTS_DIR"

log "Generating LaunchAgent plist (home=$HOME)"
sed -e "s|__HOME__|$HOME|g" \
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
VERIFY_PORT="$PIPER_PORT"
if [ -f "$CONFIG_FILE" ]; then
    VERIFY_PORT=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('piper_port', $PIPER_PORT))" 2>/dev/null || echo "$PIPER_PORT")
fi
log "Waiting for Piper HTTP server on port $VERIFY_PORT..."
MAX_WAIT=15
WAITED=0
while ! curl -s "localhost:$VERIFY_PORT/voices" >/dev/null 2>&1; do
    sleep 1
    WAITED=$((WAITED + 1))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        err "Piper HTTP server did not start within ${MAX_WAIT}s"
        err "Check logs at: $TTS_DIR/logs/piper-server.log"
        err "Try running manually: $TTS_DIR/scripts/piper_http_launch.sh"
        exit 1
    fi
done
log "Piper HTTP server is running on port $VERIFY_PORT"

log ""
log "Setup complete! Summary:"
log "  Config:      $CONFIG_FILE"
log "  Scripts:     $TTS_DIR/scripts/"
log "  Queue:       $TTS_DIR/queue/"
log "  Hooks:       $HOOKS_FILE"
log "  LaunchAgent: $PLIST_DEST"
log "  Piper:       http://localhost:$VERIFY_PORT"
log ""
log "Try: echo 'Hello world' | python3 $TTS_DIR/scripts/clean_text.py"
log "Optional: brew install terminal-notifier — click macOS notifications to play queued replies when notifications are enabled in the menu."
