# <img src="icons/tmnt-notification-queued.png" alt="Read aloud" width="40" /> Cursor Read Aloud

A local tool that reads Cursor AI agent responses aloud via a macOS menu bar dropdown. Uses [Piper TTS](https://github.com/OHF-Voice/piper1-gpl) with the `en_US-libritts_r-medium` voice model for fast, offline speech synthesis.

## How It Works

1. A Cursor `afterAgentResponse` hook captures each assistant reply and queues it as a JSON file
2. A SwiftBar menu bar plugin lists queued responses **by agent thread** (with play/pause, start over, and section labels). **Setup** copies TMNT icons into `~/.cursor/tts/icons/`; the menu bar shows a calm turtle when the queue is empty and a “queued” turtle when there are waiting messages. **Notifications** (terminal-notifier) default to the queued TMNT art as the **content image** (large attachment on the right).
3. Open a thread submenu and pick a message to clean the text (strip code blocks, tables-to-prose, etc.) and play it via Piper TTS
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
  "model": "en_US-libritts_r-medium",
  "notifications_enabled": false,
  "notification_icon": "~/.cursor/tts/icons/tmnt-notification-queued.png",
  "notification_sender": "",
  "terminal_notifier_app": "",
  "notification_sound": "default"
}
```

- **default_speed**: Playback speed multiplier (0.75x to 2.0x). Also adjustable from the menu bar speed submenu.
- **model**: Piper voice id (no file extension), matching the base name of files in `models/`, e.g. `en_US-ryan-high`. Changing this from the **Voice** menu restarts Piper when the server is running.
- **speaker_id**: Piper speaker index (0-903 for `en_US-libritts_r-medium`; use `0` for the single-speaker voices). Selecting a non-LibriTTS voice from the menu sets this to `0` automatically.
- **piper_port**: Port for the local Piper HTTP server (used by the launch script and `play.sh`).
- **notifications_enabled**: When `true`, each new queued reply triggers a macOS notification. With **terminal-notifier** installed (stock or custom app below), **clicking** the notification runs `play.sh` for that item. Without it, a plain AppleScript notification appears (open the Read Aloud menu to play). Toggle from the menu bar without editing JSON.
- **notification_icon**: Path to a PNG/JPEG passed to terminal-notifier’s **`-contentImage`** (expanded `~`). That flag still works on modern macOS; **`-appIcon`** does not (broken since Big Sur). Default is `~/.cursor/tts/icons/tmnt-notification-queued.png`. Set `""` for no custom image.
- **notification_sender**: Optional bundle ID of another **installed** app. When set, **`-sender`** forces the **left** banner icon to that app’s icon. Leave **`""`** if you use a **custom notifier `.app`** (below)—otherwise **`-sender`** overrides your custom app’s icon.
- **terminal_notifier_app**: Optional path to the **custom** `.app` from **`build_read_aloud_notifier_app.sh`**. When **non-empty**, that bundle is used first. When **empty**, `notify_queued.sh` still tries **`~/Applications/CursorReadAloudNotifier.app`** automatically (the build script’s default output). If that folder is missing, it falls back to stock **`/Applications/terminal-notifier.app`** — which shows the **Terminal** icon on the left. **`hook.log`** lines **`notifier binary: …`** show which binary ran.
- **notification_sound**: Sound name for the banner chime. **Not** set in System Settings for the tone itself—you choose the name here (and **System Settings → Notifications** only controls things like **alert style** and whether notifications are allowed). Use **`default`** for terminal-notifier’s default, or any built-in **alert sound name** (same names as **System Settings → Sound → Sound Effects**—the list comes from Apple’s classic alert set and matches what **`terminal-notifier -help`** describes for **`-sound`**). **Custom** sounds: put **`.aiff`**, **`.wav`**, **`.caf`**, or **`.m4a`** files in **`~/Library/Sounds`**; the **sound name** is the **filename without extension** (Apple’s rule). The SwiftBar menu shows **one list**: built-ins, then a disabled **`---`** row, then any custom files—no extra section header. Same value is passed to **terminal-notifier** **`-sound`** and to AppleScript **`sound name`** when falling back. You can also edit JSON or use **`set_notification_sound.sh`**.

### Notification icons (why two icons?)

| Place             | What it is                                     | How to control                                                                                                                                                                                    |
| ----------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Left** (small)  | The **sending app’s** icon (always shown)      | Use **`terminal_notifier_app`** for your own TMNT (or leave unset for stock terminal-notifier). Optionally **`notification_sender`** to impersonate another installed app. **Cannot be removed.** |
| **Right** (large) | **Content image** from **`notification_icon`** | Your TMNT “queued” PNG (or any path you set).                                                                                                                                                     |

### Custom notifier app (your icon on the left)

1. Install a working **terminal-notifier** (e.g. `brew install --cask terminal-notifier`, or build a newer `.app` for macOS 15+ per **Troubleshooting**).
2. From the repo: **`bash scripts/build_read_aloud_notifier_app.sh`**
   - Copies `terminal-notifier.app` to **`~/Applications/CursorReadAloudNotifier.app`** (override: `bash scripts/build_read_aloud_notifier_app.sh /path/to/terminal-notifier.app "$HOME/Applications/Out.app" icons/tmnt-icon.png`).
   - Uses **`icons/tmnt-icon.png`** for the **app** icon (good for the small left glyph); pass a different PNG as the 3rd argument if you prefer.
3. Add to **`~/.cursor/tts/config.json`**: `"terminal_notifier_app": "/Users/YOU/Applications/CursorReadAloudNotifier.app"` (use your real path).
4. First launch: if macOS blocks it, **right‑click → Open** once, or `xattr -cr ~/Applications/CursorReadAloudNotifier.app`.
5. Re-run **`bash scripts/setup.sh`** so **`notify_queued.sh`** is current, or copy **`scripts/notify_queued.sh`** to **`~/.cursor/tts/scripts/`**. Keep **`notification_sender`** empty.

## Menu Bar Controls

| Action                  | Description                                                                                                                       |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Click a queued response | Clean text and play via TTS                                                                                                       |
| Stop Playback           | Kill active audio                                                                                                                 |
| Notifications On/Off    | Enable or disable macOS notifications when a reply is queued (see **notifications_enabled**)                                      |
| Notification sound      | Submenu: built-ins, **`---`**, then **`~/Library/Sounds`** → **`notification_sound`**                                             |
| Speed submenu           | Change playback speed                                                                                                             |
| Voice submenu           | Switch Piper model (requires the matching `.onnx` + `.onnx.json` in `~/.cursor/tts/models/`); restarts Piper when listening is on |
| Clear All Messages      | Mark all responses as played                                                                                                      |
| Open Config             | Edit config.json in default editor                                                                                                |
| Open Logs               | Browse log directory                                                                                                              |

### Hotkeys (SwiftBar + optional Hammerspoon)

| Shortcut           | Action |
| ------------------ | ------ |
| **ctrl+shift+p**   | **Play Latest** — newest queued message (SwiftBar global shortcut; also in the menu) |
| **ctrl+shift+space** | **Pause / Resume** during playback (when the Pause/Resume row is shown) |
| **ctrl+Play** (dedicated Play/Pause key) | **Play Latest** — [Hammerspoon](https://www.hammerspoon.org/) + Accessibility; if the dedicated key never fires in HS, use **ctrl+F8** (same row as Play on many Macs) |
| **Play** (alone)   | If TTS is playing or the queue has items: same as menu Pause/Resume / play latest; otherwise the key passes through to Music / Spotify |

Hammerspoon loads **`~/.cursor/tts/scripts/hammerspoon-tts.lua`** (installed by `setup.sh`). Open Hammerspoon once, grant **Accessibility**, run **`bash scripts/setup.sh`** if `~/.hammerspoon` did not exist yet, then **Reload Config** in Hammerspoon.

**If media keys do nothing from Hammerspoon:** Reload and confirm **`cursor-read-aloud: taps started`** in **Hammerspoon → Console**. Copy the repo’s **`config/hammerspoon-tts.lua`** to **`~/.cursor/tts/scripts/hammerspoon-tts.lua`** and reload. **Debug:** Two different paths on purpose: `touch ~/.cursor/tts/.hammerspoon-tts-debug` is only an **on-switch** (it can stay **empty**). **`~/.cursor/tts/logs/hammerspoon-media-debug.log`** is the **log** (created when debug is on and you reload Hammerspoon, then grows as keys fire). Console also shows `[cursor-read-aloud]` lines. Press **Play** and **volume** once each; if the log never gains **`NSSystemDefined aux`** lines, the OS isn’t delivering those events to Hammerspoon (try **Input Monitoring** for Hammerspoon in **System Settings → Privacy & Security** if listed; avoid **Secure Input**, e.g. password fields). **Fallback:** try **ctrl+F8** (top-row Play/Pause) — the same script may receive F8+ctrl even when the dedicated Play key does not.

The SwiftBar plugin is named **`cursor-read-aloud.5s.sh`**, so SwiftBar runs it about **every 5 seconds** (see [SwiftBar plugin naming](https://github.com/swiftbar/SwiftBar#plugin-naming)). On each run it lists **`~/Library/Sounds`** once—usually a **tiny** cost (single `readdir`, typically a handful of files) next to the rest of the script; the menu-bar image uses a **cached** base64 file. To refresh less often, rename the plugin (e.g. **`cursor-read-aloud.30s.sh`**) and re-copy it to your plugins folder.

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
- **Notifications not appearing**: Confirm **Notifications: On** in the menu. Check `hook.log` for lines starting with `notify:` to see which delivery method ran and whether it succeeded.
- **Notification flashes away too fast**: Open **System Settings → Notifications → terminal-notifier** (or **Script Editor** for osascript) and switch Alert Style to **Persistent**.
- **terminal-notifier shows nothing (Sequoia / macOS 15+)**: The Homebrew version silently fails on newer macOS (exits 0, no banner). Build from source with a bumped deployment target — see [this GitHub issue](https://github.com/julienXX/terminal-notifier/issues/312). Quick steps: `cd /tmp && git clone https://github.com/julienXX/terminal-notifier.git && cd terminal-notifier`, then `sed -i '' 's/MACOSX_DEPLOYMENT_TARGET = 10.10/MACOSX_DEPLOYMENT_TARGET = 15.0/g' "Terminal Notifier.xcodeproj/project.pbxproj"`, `xcodebuild -project "Terminal Notifier.xcodeproj" -configuration Release -arch arm64`, and `cp -R build/Release/terminal-notifier.app /Applications/`. The script checks `/Applications/terminal-notifier.app` first, then `PATH`, then osascript.
