# Ideas backlog

Things the owner wants to explore later — not scheduled, just don't lose them.

- **cmux vs tmux** (noted 2026-07-18): owner is committing to a terminal multiplexer for team sessions (replies/injection require it) but isn't attached to tmux specifically. Evaluate cmux as an alternative before building more tmux-coupled tooling. Today's coupling points: `team.sh` (tmux new-session), `inject_prompt.sh` (tmux send-keys), `team_map.json` (tmux target names), `panel-ws.ts` focus/kill actions.
- **Android wrapper app for the mobile page** (noted 2026-07-18): a thin WebView wrapper around the Room of Devs mobile page so it can use Android 17's floating-bubble multitasking ("turn your apps into floating bubbles over your main screen"). Would give a persistent floating room widget instead of a pinned Chrome tab. Needs: WebView + the mobile token baked into the start URL (Tailscale hostname), maybe notification integration for hand-raised events later.
