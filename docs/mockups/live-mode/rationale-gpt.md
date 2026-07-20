# Live line — rationale

## Core idea

The expanded player becomes a **line with Karai**, not a stack of audio files. Recent user/agent turns establish conversational continuity; audio is an affordance on each finished response rather than the page's organizing metaphor.

Live mode deliberately changes the room: a green phone-edge light, an always-visible “LIVE AUDIO ON” cost banner, and a chronological spoken transcript make it feel like joining an active channel. The transcript uses one vertical rail so intermediates read as a continuous thought, not separate finished messages.

## Kept

- Per-agent opt-in, because synthesis has a real marginal cost.
- The existing text + dictation reply row, always reachable and usable while the agent works.
- Acknowledgement audio after send, shown as a small receipt rather than a new message.
- Normal play controls on completed responses and normal final-message behavior.
- One audio stream: live mode exposes only pause and end, never competing clips or a seek bar.

## Changed or dropped

- The large album-art player is replaced by a compact identity header. In conversation, transcript and reply deserve the vertical space.
- “Working” clears the prior response from the focal area but preserves it in history, so the action feels continuous without losing context.
- The live transcript labels each intermediate as “spoken” or “speaking now”; karaoke highlighting and scrubbing are omitted because intermediates are ephemeral and should feel immediate.
- “Go live” remains available in the working state through the persistent identity action; live is optional per turn, not a sticky global preference.

## Cost visibility

Green normally means activity, but live mode adds three redundant signals: a glowing frame, explicit all-caps status, and the text “intermediates use credits.” The signal persists for the entire paid state and disappears immediately on exit.

## Risk

Intermediate agent narration can be noisy or misleading before the agent has verified its conclusion. The chronological rail helps frame it as progress, but the product may still need rate limits or agent-side rules for which intermediate messages deserve synthesis.
