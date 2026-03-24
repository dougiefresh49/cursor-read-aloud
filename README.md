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
- Download the `en_US-libritts_r-medium` voice model (~79 MB)
- Create the directory structure under `~/.cursor/tts/`
- Copy scripts, install the Cursor hook, start the Piper HTTP server, and install the SwiftBar plugin

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
- **speaker_id**: Piper voice speaker (0-903 for libritts_r, 0 = best quality).
- **piper_port**: Port for the local Piper HTTP server.

## Menu Bar Controls

| Action | Description |
|---|---|
| Click a queued response | Clean text and play via TTS |
| Stop Playback | Kill active audio |
| Speed submenu | Change playback speed |
| Clear Queue | Mark all responses as played |
| Open Config | Edit config.json in default editor |
| Open Logs | Browse log directory |

## Text Cleaning

Before synthesis, responses are cleaned to remove non-prose content:

- Fenced code blocks (triple backticks)
- Inline code spans
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
- **Piper not starting**: Run manually: `python3 -m piper.http_server -m en_US-libritts_r-medium --data-dir ~/.cursor/tts/models --port 5111`
- **Hook not firing**: Verify `~/.cursor/hooks.json` exists and Cursor is restarted
- **SwiftBar not showing**: Ensure SwiftBar is running and the plugin is in the correct plugins directory
