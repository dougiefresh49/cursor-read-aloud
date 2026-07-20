# Fable concept rationale

## Core idea

The expanded view for reply-capable agents becomes a **messaging thread**, not a
media player. Turns persist as bubbles (your replies right, agent left with a
per-message play button). "The old message goes away" is satisfied by scrolling
up naturally — history stays reachable, which a call metaphor can't give you.

Live mode is a **pill in the header** (where a call app puts its status): "Go
live" → red "LIVE" with a blinking ring. While ON, intermediate progress
messages stream in as *dimmer, smaller* bubbles tagged PROGRESS — visually
subordinate to real turn-final messages, because they're ephemeral narration,
not conclusions. The currently-spoken text karaoke-highlights inside its bubble.

## What I kept / dropped

- Kept: ack chip in-thread (small pill with 🔊 — it's a real audio moment, so it
  gets a real place in the thread); working state with avatar pulse + tool-run
  hint; reply always available; minimal live controls (one End-live button —
  play/pause dropped because pausing "live" contradicts the metaphor; if you
  need to stop listening, you end live).
- Dropped: separate "working view" screen — working is just the latest thread
  state, no mode switch. Dropped scrubbing/prev/next in live.
- Changed: final response while live stays in-thread and auto-speaks; ending
  live returns the normal transport row.

## Cost visibility

The LIVE pill is loud (red, blinking) and the bottom note says "uses more
credits while on." Live is per-agent and dies with the working turn's end —
it does NOT persist across turns unless re-tapped (a deliberate cost guard;
one tap = one supervised turn).

## One risk

Progress bubbles arrive faster than the voice reads them; the audio queue drifts
behind the text. Mitigation shown in mockup: only the bubble currently being
spoken gets the wave icon; backlog bubbles show "spoken" ✓ or nothing, and the
server should skip stale intermediates (speak only the newest unspoken one)
rather than reading a backlog.
