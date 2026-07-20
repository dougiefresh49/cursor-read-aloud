# Concept review — Live conversation mode

Judged vs brief: conversation feel, live-mode clarity, cost visibility, vanilla single-file implementability.

## GPT — “Live line”
**Strengths**
- Clearest “you are paying” signal: green phone-edge + always-visible `LIVE AUDIO ON` / “intermediates use credits.”
- Chronological stream rail reads as one continuous thought, not a pile of finished clips; pause + End live dock matches the brief.
- Leanest mockup (~80 LOC structure): shared chrome + `data-view` switching — easy to port.

**Weaknesses**
- Live state swaps out the turn history for a dedicated transcript — breaks conversational continuity while listening.
- Working is a dashed empty card (mode room), not “the old message cleared into the thread.”
- Final/idle feel thinner as a chat; less “another AI in the room,” more “open a line.”

## Grok (mine) — thread + armed LIVE
**Strengths**
- Full A–D coverage with shared history: intermediates as thread bubbles, karaoke only on the active clip, pause + End live, reply always present.
- Best credit-discipline UX: LIVE off by default, **armed** after reply (invite, not auto-on), cost bar with clip count.
- Closest token match to `mobile.html` (surfaces, accent, reply row, classic dock returning only when live is off).

**Weaknesses**
- Overbuilt for a concept (~30KB, duplicated avatars/buttons, attribute visibility soup) — harder to skim/ship than the others.
- Idle/final still mount a full scrub/prev/next/speed dock — reintroduces the podcast-player metaphor the brief wants to escape.
- Working card is still a focal “empty stage”; less continuous than an inline thread status.

## Fable — messaging thread
**Strengths**
- Strongest conversation feel: me-right / agent-left bubbles; history stays; “old message goes away” = scroll, not wipe.
- Progress bubbles are dimmer + tagged — intermediates look ephemeral vs turn-finals; karaoke inside the speaking bubble.
- Working is just the latest thread state (ack chip + tools hint + Go live) — no mode-switch screen. LIVE pill (red blink) is unmistakable ON; turn-scoped live is a sharp cost guard.

**Weaknesses**
- Idle/final still show classic transport (prev/play/next/speed) — same player hangover as Grok.
- Cost copy is a quiet footer note; weaker than GPT’s banner / Grok’s clip meter. Red LIVE drifts from the green product language.
- Dropping pause in live is coherent metaphorically but fights the brief’s “play/pause at most.”

## Ranked verdict
1. **Fable** — best conversation metaphor and cleanest state model  
2. **GPT** — best live/cost clarity and most implementable mockup  
3. **Grok** — richest credit UX and state completeness, but overbuilt and still player-shaped in A/D  

## Combine into a final
Take Fable’s left/right thread, dim PROGRESS bubbles, in-thread ack, and working-as-inline-status. Steal GPT’s edge glow + explicit credits banner while LIVE is on. Keep Grok’s armed LIVE after reply, clip-count cost bar, pause + End live dock, and karaoke only on the active clip. Drop the classic scrubber from the conversation sheet; play lives on final bubbles (and optionally a slim dock only when a finished final is selected).
