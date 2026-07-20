# Design brief: "Live mode" — conversational playback for reply-capable agents

## Product context

"Room of Devs" is a personal tool: AI coding agents (Claude Code sessions with
character personas — Donatello, Karai, Splinter, etc.) work on the owner's Mac.
A dark-themed mobile web page (phone) shows a room of agent cards with avatars.
When an agent finishes a task it "raises its hand"; the owner taps it and the
response is read aloud with the character's ElevenLabs voice, streamed to the
phone (~instant start, v2.3). There's an expanded player: avatar, karaoke-style
text highlighting, play/pause, speed, prev/next, scrub bar, and — for
tmux-hosted agents — a Reply box (type or dictate; the reply is injected into
the agent's terminal; a short pre-recorded "acknowledgement" clip in the
character's voice plays, e.g. "on it boss").

Design language: near-black background (#0f1115-ish), dark cards with 1px
white/10% borders, rounded 12-16px, green accent (#4ade80), character avatar
images, system font stack, 0.9rem body text. Reference the real page at
tts-server/mobile.html in this repo (read it for colors/structure; do NOT
edit it).

## The problem (owner's words, condensed)

Replying to an agent then tapping play on its next finished message "felt like
sending an email." The original concept was "another AI dev in the room."
Desired: an ongoing-conversation feel for reply-capable agents — closer to a
voice call with transcripts, but not exactly (pausing exists, replies are
typed/dictated).

Key beats the owner described:

1. Today only the FINAL response of each turn is spoken. In the terminal there
   are intermediate assistant messages between the user's prompt and the final
   response ("I'll check the logs first…", "Found it — the tmux server cwd is
   stale…"). In live mode those should stream to the phone and be spoken as
   they happen, so the owner just listens instead of smashing play.
2. A "live" toggle/button — like the Gemini app's live button (concept
   inspiration, not 1:1) — enters this mode per-agent. Exiting returns to
   normal single-play mode.
3. After sending a reply: acknowledgement clip plays on the phone, the old
   message clears, a "working" state shows (she's working…), live button
   available to hear intermediates, reply can be sent anytime, and the final
   message lands as normal.
4. Live mode needs minimal controls: play/pause at most, or just an
   end-live button. No scrubbing.
5. Non-tmux (read-only) sessions keep the existing static expanded player
   unchanged.

## Hard constraints

- Every synthesized message costs real ElevenLabs credits. Intermediate
  messages are synthesized ONLY while live mode is active for that session.
  The design should make live mode feel clearly ON (so cost is intentional).
- Audio is one stream at a time on the phone (single <audio> element).
- Replies still use the existing input row (text + dictation). Do not design
  hands-free voice capture.
- Static/self-contained mockup only: one HTML file, no external assets, no JS
  frameworks (vanilla inline JS allowed for state-switching between mockup
  screens). Phone-frame it (~390px wide viewport centered on a dark page).
- Owner's phone: Pixel, Chrome. Dark theme only.

## Deliverables (write into your assigned output directory)

1. `concept.html` — one self-contained file showing 4 states of the expanded
   view for a reply-capable agent (tab/button switcher between states is fine):
   A. Conversation view, idle (history of recent turns, play affordance)
   B. Live mode ON (intermediates streaming in, transcript growing, minimal controls)
   C. Working state right after a reply (ack played, agent busy)
   D. Final response landed (live exited or never entered)
2. `rationale.md` — max 50 lines: the core idea, what you kept/dropped from
   the owner's description and why, how live-mode cost visibility is handled,
   and one risk.

Do NOT make any live API calls. Do not touch the repo. Design only.
