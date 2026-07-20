# Live mode rationale

## Core idea
Treat reply-capable agents as a **conversation thread**, not a podcast player. The expanded sheet becomes chat + a sticky agent header; the giant avatar/hero player only exists for non-tmux (unchanged elsewhere). Live mode is an opt-in **open channel** on that thread: intermediates stream in as bubbles and speak automatically. Exit live → back to “play the final when you want.”

## Kept
- Per-agent LIVE toggle; off by default; intermediates synthesized only while ON.
- After reply: ack clip → clear prior turn chrome → working state; reply row stays.
- Live controls = pause + End live (no scrub/speed/prev-next).
- Existing reply input + dictate; single audio stream assumed.

## Dropped / changed
- **Dropped hero avatar + always-on karaoke/scrubber** for tmux agents — that layout is “listen to a finished recording,” which is the email feel. Thread + compact dock is the call-with-transcripts feel.
- **Dropped auto-live after reply.** Owner said live should be available; I make it **armed** (glowing invite) on the working card, not auto-on — credits stay intentional.
- **Karaoke only on the active live clip**, not the whole history.
- **No hands-free mic**; reply row unchanged.

## Cost visibility
LIVE off = outline pill, quiet. LIVE on = filled green + pulsing orb + green avatar ring + **“Synthesizing intermediates” cost bar** with clip count. Working copy says credits only while LIVE is on. End live is red-tinted and one tap away.

## One risk
A long live turn can flood the thread with short intermediate bubbles and burn credits faster than the owner notices if they leave LIVE on and walk away — the cost bar helps, but an idle auto-end (e.g. after N silent minutes) may still be needed later.
