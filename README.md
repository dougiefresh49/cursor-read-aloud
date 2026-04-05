# Cursor Read Aloud

A local tool that reads Cursor AI agent responses aloud via a macOS menu bar dropdown. Uses [Piper TTS](https://github.com/OHF-Voice/piper1-gpl) with the `en_US-libritts_r-medium` voice model for fast, offline speech synthesis.

## How It Works

1. A Cursor `afterAgentResponse` hook captures each assistant reply and queues it as a JSON file
2. A SwiftBar menu bar plugin shows queued responses with estimated duration
3. Click a response to clean the text (strip code blocks, tables-to-prose, etc.) and play it via Piper TTS
4. Falls back to macOS `say` if Piper is unavailable

## Prerequisites

- macOS
- Python 3.9+
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install --cask swiftbar`)

## Setup

```bash
bash scripts/setup.sh
```

This will:

- Install `piper-tts` via pip
- Download the `en_US-libritts_r-medium` voice model (\~79 MB) plus optional English voices: Norman (medium), Northern English male (medium), and Ryan (high, ONNX \~121 MB)—skipped if the `.onnx` / `.onnx.json` pairs are already in `~/.cursor/tts/models/`
- Create the directory structure under `~/.cursor/tts/`
- Copy scripts, install the Cursor hook, install a LaunchAgent that starts Piper via `piper_http_launch.sh` (reads `model` and `piper_port` from config), and install the SwiftBar plugin

## Configuration

Edit `~/.cursor/tts/config.json`:

```json
{
  "piper_port": 5111,
  "speaker_id": 0,
  "default_speed": 1.25,
  "model": "en_US-libritts_r-medium"
}
```

- **default_speed**: Playback speed multiplier (0.75x to 2.0x). Also adjustable from the menu bar speed submenu.
- **model**: Piper voice id (no file extension), matching the base name of files in `models/`, e.g. `en_US-ryan-high`. Changing this from the **Voice** menu restarts Piper when the server is running.
- **speaker_id**: Piper speaker index (0-903 for `en_US-libritts_r-medium`; use `0` for the single-speaker voices). Selecting a non-LibriTTS voice from the menu sets this to `0` automatically.
- **piper_port**: Port for the local Piper HTTP server (used by the launch script and `play.sh`).

## Menu Bar Controls

| Action                  | Description                                                                                                                       |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Click a queued response | Clean text and play via TTS                                                                                                       |
| Stop Playback           | Kill active audio                                                                                                                 |
| Speed submenu           | Change playback speed                                                                                                             |
| Voice submenu           | Switch Piper model (requires the matching `.onnx` + `.onnx.json` in `~/.cursor/tts/models/`); restarts Piper when listening is on |
| Clear Queue             | Mark all responses as played                                                                                                      |
| Open Config             | Edit config.json in default editor                                                                                                |
| Open Logs               | Browse log directory                                                                                                              |

## Manual Enqueue

If listening was paused when a response came in, or you want to queue arbitrary text, use the `enqueue_manual.sh` script. It reads text from stdin and creates a queue entry that shows up in the SwiftBar menu like any hook-captured response.

```bash
# Queue whatever is on your clipboard (e.g. copy an assistant reply, then run this)
pbpaste | ~/.cursor/tts/scripts/enqueue_manual.sh "My thread title"

# Pipe from a file
~/.cursor/tts/scripts/enqueue_manual.sh "Review notes" < ~/Desktop/missed-reply.md

# Quick inline text
echo "Remember to update the API keys" | ~/.cursor/tts/scripts/enqueue_manual.sh
```

The first argument is an optional title shown in the menu bar dropdown (defaults to "Manual enqueue"). The script writes a JSON file to `~/.cursor/tts/queue/` with the same structure the hook produces, so playback, text cleaning, and queue management all work identically.

### Raycast Script Commands

Three optional Raycast scripts live in `scripts/raycast/` (same metadata style as other projects: `@raycast.schemaVersion`, title, packageName **Cursor Read Aloud**). Add the repo folder (or symlink these `.sh` files) under **Raycast → Extensions → Script Commands** so they appear in the Raycast root search.

| Script                            | What it does                                                                      |
| --------------------------------- | --------------------------------------------------------------------------------- |
| `enqueue-read-aloud-clipboard.sh` | `pbpaste` → `enqueue_manual.sh` with optional thread title (silent HUD).          |
| `enqueue-read-aloud-file.sh`      | First argument: file path; second: optional title. Reads the file into the queue. |
| `enqueue-read-aloud-text.sh`      | First argument: short inline text; second: optional title.                        |

All three expect `~/.cursor/tts/scripts/enqueue_manual.sh` to exist (run `scripts/setup.sh` once).

## Text Cleaning

Before synthesis, responses are cleaned to remove non-prose content:

- Fenced code blocks (triple backticks)
- Inline code tokens humanized (e.g. `src/lib/document-prompts.ts` → "src lib document prompts T S")
- camelCase, kebab-case, snake_case split into words; file extensions spoken naturally
- Code-like lines (imports, shell commands, high symbol density)
- Markdown images
- Markdown tables are converted to prose
- Headers become sentences with pauses
- Bold/italic markers stripped, link URLs removed (text kept)

## File Layout

```
~/.cursor/
  hooks.json                          # afterAgentResponse hook registration
  tts/
    config.json                       # voice, speed, port settings
    models/                           # Piper ONNX model files
    queue/                            # unplayed response JSON files
    played/                           # responses after playback
    scripts/                          # ingest, play, stop, clean, helpers
    logs/                             # piper-server.log, hook.log
```

## Troubleshooting

- **No audio**: Check `~/.cursor/tts/logs/hook.log` and `piper-server.log`
- **Piper not starting**: Check `~/.cursor/tts/logs/piper-server.log`. To run the same process as LaunchAgent: `~/.cursor/tts/scripts/piper_http_launch.sh`
- **Hook not firing**: Verify `~/.cursor/hooks.json` exists and Cursor is restarted
- **SwiftBar not showing**: Ensure SwiftBar is running and the plugin is in the correct plugins directory
