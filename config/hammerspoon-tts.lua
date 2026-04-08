-- Cursor Read Aloud — Play/Pause media key for TTS.
-- Debug: `touch ~/.cursor/tts/.hammerspoon-tts-debug` — logs go to Console AND
-- ~/.cursor/tts/logs/hammerspoon-media-debug.log (the touch file stays empty; that is normal).

local home = os.getenv("HOME") or ""
local tts = home .. "/.cursor/tts"
local scripts = tts .. "/scripts"
local pidFile = tts .. "/.playback-pid"
local queueDir = tts .. "/queue"
local playLatest = scripts .. "/play_latest.sh"
local mediaControl = scripts .. "/media_control.sh"
local restartScript = scripts .. "/restart.sh"
local stopScript = scripts .. "/stop.sh"
local debugFlagPath = tts .. "/.hammerspoon-tts-debug"
local debugFileLog = tts .. "/logs/hammerspoon-media-debug.log"

local NX_KEYTYPE_PLAY = 16
local NX_KEYDOWN = 0x0A00

-- Resolve the event type — name varies across Hammerspoon versions.
local types = hs.eventtap.event.types
local sysDefinedType = types.NSSystemDefined or types.systemDefined or 14

if _cursorReadAloudStopTaps then
  pcall(_cursorReadAloudStopTaps)
end

local flagsTap
local mediaTap
local f8Tap

local function readPid()
  local f = io.open(pidFile, "r")
  if not f then
    return nil
  end
  local line = f:read("*l") or ""
  f:close()
  return line:match("^%s*(%d+)%s*$")
end

local function ttsPlaybackAlive()
  local pid = readPid()
  if not pid then
    return false
  end
  local ok = os.execute("/bin/kill -0 " .. pid .. " 2>/dev/null")
  return ok == true or ok == 0
end

local function queueHasItems()
  local p = io.popen(string.format(
    '/usr/bin/find %q -maxdepth 1 -name "*.json" -print -quit 2>/dev/null',
    queueDir
  ))
  if not p then
    return false
  end
  local first = p:read("*l")
  p:close()
  return first ~= nil and first ~= ""
end

local function runScript(path)
  if path == nil or path == "" then
    return
  end
  hs.task.new("/bin/bash", nil, { path }):start()
end

local function nseventData(ev)
  local raw = ev:getRawEventData()
  if type(raw) ~= "table" or raw.NSEventData == nil then
    return nil
  end
  return raw.NSEventData
end

local debugEnabled = (hs.fs.attributes(debugFlagPath) ~= nil)

local logDirEnsured = false
local function appendFileDebug(msg)
  if not debugEnabled then
    return
  end
  if not logDirEnsured then
    os.execute(string.format("/bin/mkdir -p %q", tts .. "/logs"))
    logDirEnsured = true
  end
  local f = io.open(debugFileLog, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg .. "\n")
    f:close()
  end
end

local function dbg(msg)
  if not debugEnabled then
    return
  end
  print("[cursor-read-aloud] " .. msg)
  appendFileDebug(msg)
end

local function isPlayPauseKeyDownLegacy(nx)
  nx = tonumber(nx)
  if not nx then
    return false
  end
  local key = (nx >> 16) & 0xFFFF
  local keyState = nx & 0xFF00
  if key ~= NX_KEYTYPE_PLAY then
    return false
  end
  return keyState == NX_KEYDOWN or keyState == 0x0800
end

local function isMediaPlayKeyDown(ev, sk)
  sk = sk or ev:systemKey()
  if type(sk) == "table" and sk.down then
    if sk.key == "PLAY" then
      return true
    end
    local kc = tonumber(sk.keyCode or sk.numericValue)
    if sk.key == "undefined" and kc == NX_KEYTYPE_PLAY then
      return true
    end
  end
  local nx = nseventData(ev)
  return nx ~= nil and isPlayPauseKeyDownLegacy(nx)
end

local ctrlFromFlags = false
local function updateCtrlFromFlags(ev)
  local f = ev:getFlags()
  ctrlFromFlags = f ~= nil and f.ctrl == true
  return false
end

local function ctrlHeldForMedia(ev)
  if ctrlFromFlags then
    return true
  end
  local m = hs.eventtap.checkKeyboardModifiers()
  if m and m.ctrl then
    return true
  end
  local f = ev and ev.getFlags and ev:getFlags()
  return f ~= nil and f.ctrl == true
end

local function actOnPlay(ev, label)
  local sk = ev:systemKey()
  local nx = nseventData(ev)
  local m = hs.eventtap.checkKeyboardModifiers()
  dbg(string.format(
    "%s sk.key=%s sk.down=%s nx=0x%x ctrlFromFlags=%s mods.ctrl=%s",
    label,
    tostring(sk and sk.key),
    tostring(sk and sk.down),
    tonumber(nx) or 0,
    tostring(ctrlFromFlags),
    tostring(m and m.ctrl)
  ))

  if ctrlHeldForMedia(ev) then
    dbg("→ play_latest.sh (" .. label .. ")")
    runScript(playLatest)
    return true
  end

  if ttsPlaybackAlive() or queueHasItems() then
    dbg("→ media_control.sh (" .. label .. ")")
    runScript(mediaControl)
    return true
  end

  return false
end

local function onSystemDefined(ev)
  if debugEnabled then
    appendFileDebug("onSystemDefined callback fired (raw event received)")
  end

  local sk = ev:systemKey()
  if debugEnabled and type(sk) == "table" and next(sk) ~= nil then
    appendFileDebug(string.format(
      "NSSystemDefined aux key=%s down=%s keyCode=%s",
      tostring(sk.key),
      tostring(sk.down),
      tostring(sk.keyCode or sk.numericValue)
    ))
  end

  -- PREVIOUS (rewind) → restart current playback from the beginning
  if type(sk) == "table" and sk.down and sk.key == "PREVIOUS" then
    if ttsPlaybackAlive() then
      dbg("PREVIOUS → restart.sh")
      runScript(restartScript)
      return true
    end
    return false
  end

  -- NEXT (fast-forward) → stop current, play next queued message
  if type(sk) == "table" and sk.down and sk.key == "NEXT" then
    if ttsPlaybackAlive() then
      dbg("NEXT → stop + play_latest")
      runScript(stopScript)
      hs.timer.doAfter(0.3, function() runScript(playLatest) end)
      return true
    end
    return false
  end

  if not isMediaPlayKeyDown(ev, sk) then
    return false
  end

  return actOnPlay(ev, "mediaKey")
end

local f8Keycode = hs.keycodes.map and hs.keycodes.map.f8

local function onF8KeyDown(ev)
  if not f8Keycode or ev:getKeyCode() ~= f8Keycode then
    return false
  end
  if not ctrlHeldForMedia(ev) then
    return false
  end
  dbg("ctrl+F8 keyDown")
  runScript(playLatest)
  return true
end

flagsTap = hs.eventtap.new({ types.flagsChanged }, updateCtrlFromFlags)
mediaTap = hs.eventtap.new({ sysDefinedType }, onSystemDefined)
f8Tap = f8Keycode and hs.eventtap.new({ types.keyDown }, onF8KeyDown) or nil

_cursorReadAloudStopTaps = function()
  if mediaTap then
    mediaTap:stop()
    mediaTap = nil
  end
  if f8Tap then
    f8Tap:stop()
    f8Tap = nil
  end
  if flagsTap then
    flagsTap:stop()
    flagsTap = nil
  end
end

if hs.eventtap.isSecureInputEnabled and hs.eventtap.isSecureInputEnabled() then
  print("cursor-read-aloud: WARNING — Secure Input is on; taps often miss keys while a password field is focused.")
end

if flagsTap then
  flagsTap:start()
end
if mediaTap then
  mediaTap:start()
end
if f8Tap then
  f8Tap:start()
end

if mediaTap then
  local resolvedName = (types.NSSystemDefined and "NSSystemDefined")
    or (types.systemDefined and "systemDefined")
    or "14(hardcoded)"
  print("cursor-read-aloud: taps started — sysDefinedType resolved as "
    .. tostring(sysDefinedType) .. " (" .. resolvedName .. ")"
    .. (f8Tap and ", ctrl+F8 active" or ", no F8 keycode") .. ".")
  print("cursor-read-aloud: debug flag: " .. debugFlagPath)
  print("cursor-read-aloud: debug log:  " .. debugFileLog)
  if debugEnabled then
    appendFileDebug(string.format(
      "startup — sysDefinedType=%s (%s) f8Keycode=%s",
      tostring(sysDefinedType),
      resolvedName,
      tostring(f8Keycode)
    ))
  end
else
  print("cursor-read-aloud: FAILED to create system-defined tap")
end
