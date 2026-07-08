import "./style.css";
import { invoke } from "@tauri-apps/api/core";
import {
  LogicalPosition,
  LogicalSize,
  PhysicalPosition,
  PhysicalSize,
  currentMonitor,
  getCurrentWindow,
} from "@tauri-apps/api/window";

type AgentState = "working" | "hand_raised" | "speaking" | "idle";

interface AgentView {
  sessionId: string;
  character: string;
  name: string;
  state: AgentState;
  raisedCount: number;
  supersededCount: number;
  muted: boolean;
  isTeam: boolean;
}

interface WsConfig {
  token: string;
  port: number;
}

const HOLD_MS = 300;
const RECONNECT_MS = 2000;
const KILL_ARM_MS = 2000;
const FULL_MIN_SIZE = new LogicalSize(300, 240);
const DOCK_MIN_SIZE = new LogicalSize(88, 56);
const DOCK_AVATAR_STEP = 44;
const DOCK_PADDING = 28;
const DOCK_EXPAND_WIDTH = 30;
const DOCK_HEIGHT = 96;
const DOCK_BOTTOM_GAP = 12;

const app = document.querySelector<HTMLDivElement>("#app")!;
let ws: WebSocket | null = null;
let connected = false;
let agents: AgentView[] = [];
const staleSessions = new Set<string>();
const killArmed = new Map<string, ReturnType<typeof setTimeout>>();
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let dockMode = false;
let savedWindowFrame: { size: PhysicalSize; position: PhysicalPosition } | null = null;

const stateLabels: Record<AgentState, string> = {
  working: "working",
  hand_raised: "hand raised",
  speaking: "speaking",
  idle: "idle",
};

const icons = {
  pause: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14M16 5v14"/></svg>`,
  stop: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7h10v10H7z"/></svg>`,
  replay: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7h8a4 4 0 1 1-3.2 6.4"/><path d="M7 7v5H2"/></svg>`,
  terminal: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 8 3 3-3 3"/><path d="M12 16h5"/><rect x="3" y="4" width="18" height="16" rx="2"/></svg>`,
  power: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v8"/><path d="M7.05 7.05a7 7 0 1 0 9.9 0"/></svg>`,
  info: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/></svg>`,
  dock: `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="6" width="14" height="9" rx="4.5"/><path d="m8 18 4 3 4-3"/></svg>`,
  expand: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 14 5-5 5 5"/></svg>`,
  close: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>`,
} as const;

function send(msg: object) {
  if (ws?.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
  }
}

function setConnected(up: boolean) {
  connected = up;
  render();
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, RECONNECT_MS);
}

function avatarSrc(agent: AgentView): string {
  const character = (agent.character ?? "default").toLowerCase();
  const variant = agent.state === "speaking" ? "speaking" : "idle";
  return `avatars/tmnt/${character}/${variant}.png`;
}

function initials(name: string): string {
  return name
    .split(/\s+/)
    .map((w) => w[0] ?? "")
    .join("")
    .slice(0, 2)
    .toUpperCase();
}

function renderCard(agent: AgentView): string {
  const greyed = !connected || staleSessions.has(agent.sessionId);
  const mutedClass = agent.muted ? " muted" : "";
  const teamOnly = !agent.isTeam;
  const killIsArmed = killArmed.has(agent.sessionId);
  const safeName = escapeHtml(agent.name);
  const raisedChip =
    agent.state === "hand_raised"
      ? `<span class="chip raised" title="Hand raised">✋</span>`
      : "";
  const queueChip =
    agent.raisedCount > 0
      ? `<span class="chip queue" title="Queued">${agent.raisedCount}</span>`
      : "";
  const supersededChip =
    agent.supersededCount > 0
      ? `<span class="chip superseded" title="Superseded">${agent.supersededCount}</span>`
      : "";

  return `
    <div
      class="card state-${agent.state}${greyed ? " disconnected" : ""}${staleSessions.has(agent.sessionId) ? " stale" : ""}"
      data-session="${agent.sessionId}"
      role="button"
      tabindex="0"
    >
      <div class="card-main">
        <div class="avatar-wrap">
          <img class="avatar" src="${avatarSrc(agent)}" alt="" />
          <span class="avatar-fallback">${initials(agent.name)}</span>
        </div>
        <div class="card-body">
          <div class="name${mutedClass}" title="${safeName}">${safeName}</div>
          <div class="badge state-${agent.state}">
            <span class="dot"></span>
            <span class="label">${stateLabels[agent.state]}</span>
          </div>
          <div class="chips">${raisedChip}${queueChip}${supersededChip}</div>
        </div>
      </div>
      <div class="card-actions" aria-label="Agent actions">
        <button
          type="button"
          class="icon-btn hover-btn${teamOnly ? " disabled" : ""}"
          data-hover-action="focus"
          title="${teamOnly ? "team sessions only" : "Jump to terminal"}"
          ${teamOnly ? "disabled" : ""}
        >${icons.terminal}</button>
        <button
          type="button"
          class="icon-btn hover-btn kill-btn${teamOnly ? " disabled" : ""}${killIsArmed ? " armed" : ""}"
          data-hover-action="kill"
          title="${teamOnly ? "team sessions only" : killIsArmed ? "click again to end session" : "End session"}"
          ${teamOnly ? "disabled" : ""}
        >${icons.power}</button>
        <button
          type="button"
          class="icon-btn hover-btn"
          data-hover-action="status"
          title="Speak status"
        >${icons.info}</button>
      </div>
    </div>
  `;
}

function renderDockAgent(agent: AgentView): string {
  const greyed = !connected || staleSessions.has(agent.sessionId);
  const teamOnly = !agent.isTeam;
  const killIsArmed = killArmed.has(agent.sessionId);
  const safeName = escapeHtml(agent.name);

  return `
    <div
      class="dock-agent state-${agent.state}${greyed ? " disconnected" : ""}${staleSessions.has(agent.sessionId) ? " stale" : ""}"
      data-session="${agent.sessionId}"
    >
      <button
        type="button"
        class="dock-avatar-btn"
        title="${safeName} - ${stateLabels[agent.state]}"
        aria-label="${safeName}, ${stateLabels[agent.state]}"
      >
        <span class="dock-ring">
          <img class="avatar dock-avatar" src="${avatarSrc(agent)}" alt="" />
          <span class="avatar-fallback dock-fallback">${initials(agent.name)}</span>
        </span>
      </button>
      <div class="dock-actions" aria-label="Agent actions">
        <button
          type="button"
          class="icon-btn hover-btn${teamOnly ? " disabled" : ""}"
          data-hover-action="focus"
          title="${teamOnly ? "team sessions only" : "Jump to terminal"}"
          ${teamOnly ? "disabled" : ""}
        >${icons.terminal}</button>
        <button
          type="button"
          class="icon-btn hover-btn kill-btn${teamOnly ? " disabled" : ""}${killIsArmed ? " armed" : ""}"
          data-hover-action="kill"
          title="${teamOnly ? "team sessions only" : killIsArmed ? "click again to end session" : "End session"}"
          ${teamOnly ? "disabled" : ""}
        >${icons.power}</button>
        <button
          type="button"
          class="icon-btn hover-btn"
          data-hover-action="status"
          title="Speak status"
        >${icons.info}</button>
      </div>
    </div>
  `;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function dockWidth(): number {
  return Math.max(agents.length, 1) * DOCK_AVATAR_STEP + DOCK_PADDING + DOCK_EXPAND_WIDTH;
}

async function enterDockMode() {
  const win = getCurrentWindow();
  try {
    if (!savedWindowFrame) {
      const [size, position] = await Promise.all([win.outerSize(), win.outerPosition()]);
      savedWindowFrame = { size, position };
    }

    const width = dockWidth();
    await win.setMinSize(DOCK_MIN_SIZE);
    await win.setSize(new LogicalSize(width, DOCK_HEIGHT));

    const monitor = await currentMonitor();
    if (monitor) {
      const scale = await win.scaleFactor();
      const monitorX = monitor.position.x / scale;
      const monitorY = monitor.position.y / scale;
      const monitorWidth = monitor.size.width / scale;
      const monitorHeight = monitor.size.height / scale;
      await win.setPosition(
        new LogicalPosition(
          Math.round(monitorX + (monitorWidth - width) / 2),
          Math.round(monitorY + monitorHeight - DOCK_HEIGHT - DOCK_BOTTOM_GAP),
        ),
      );
    }
  } catch (err) {
    console.error("failed to enter dock mode:", err);
  }
}

async function exitDockMode() {
  const win = getCurrentWindow();
  try {
    await win.setMinSize(FULL_MIN_SIZE);
    if (savedWindowFrame) {
      await win.setSize(savedWindowFrame.size);
      await win.setPosition(savedWindowFrame.position);
      savedWindowFrame = null;
    }
  } catch (err) {
    console.error("failed to exit dock mode:", err);
  }
}

async function setDockMode(nextDockMode: boolean) {
  if (dockMode === nextDockMode) return;
  dockMode = nextDockMode;
  render();
  if (dockMode) {
    await enterDockMode();
  } else {
    await exitDockMode();
  }
}

function renderDock() {
  document.body.classList.add("dock-window");
  app.classList.add("dock-mode");
  app.innerHTML = `
    <main class="dock-shell drag-region${connected ? "" : " disconnected"}" data-tauri-drag-region>
      <div class="dock-pill" data-tauri-drag-region>
        <div class="dock-avatars">
          ${agents.length ? agents.map(renderDockAgent).join("") : '<span class="dock-empty">No agents</span>'}
        </div>
        <button type="button" class="icon-btn dock-expand no-drag" data-window-action="dock-off" title="Expand room">
          ${icons.expand}
        </button>
      </div>
    </main>
  `;

  bindHoverActions();
  bindWindowActions();
  bindGrantTargets();
  bindAvatars();
  bindDrag();
}

function render() {
  if (dockMode) {
    renderDock();
    return;
  }

  app.classList.remove("dock-mode");
  document.body.classList.remove("dock-window");
  const connClass = connected ? "up" : "down";
  app.innerHTML = `
    <header class="strip drag-region" data-tauri-drag-region>
      <span class="title" data-tauri-drag-region>Room</span>
      <div class="header-actions no-drag">
        <span class="conn-dot ${connClass}" title="${connected ? "Connected" : "Disconnected"}"></span>
        <button type="button" class="icon-btn window-btn" data-window-action="dock-on" title="Dock room">${icons.dock}</button>
        <button type="button" class="icon-btn window-btn" data-window-action="close" title="Close room">${icons.close}</button>
      </div>
    </header>
    <main class="cards${connected ? "" : " disconnected"}" id="cards">
      ${agents.length ? agents.map(renderCard).join("") : '<p class="empty">No agents</p>'}
    </main>
    <footer class="controls no-drag">
      <button type="button" class="icon-btn" data-action="pause" title="Pause / resume playback">${icons.pause}</button>
      <button type="button" class="icon-btn" data-action="stop" title="Stop playback">${icons.stop}</button>
      <button type="button" class="icon-btn" data-action="replay" title="Replay last message (free)">${icons.replay}</button>
    </footer>
  `;

  bindCards();
  bindHoverActions();
  bindControls();
  bindWindowActions();
  bindAvatars();
  bindDrag();
}

// data-tauri-drag-region needs the start-dragging permission and only covers
// the exact element — a mousedown fallback makes the whole header reliable.
function bindDrag() {
  app.querySelectorAll<HTMLElement>(".drag-region").forEach((region) => {
    region.addEventListener("mousedown", (e) => {
      if (e.button !== 0) return;
      if ((e.target as HTMLElement).closest("button, .conn-dot, .no-drag")) return;
      void getCurrentWindow().startDragging();
      e.stopPropagation();
    });
  });
}

function bindWindowActions() {
  app.querySelectorAll<HTMLButtonElement>("[data-window-action]").forEach((btn) => {
    btn.addEventListener("mousedown", (e) => e.stopPropagation());
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      const action = btn.dataset.windowAction;
      if (action === "dock-on") void setDockMode(true);
      else if (action === "dock-off") void setDockMode(false);
      else if (action === "close") void getCurrentWindow().close();
    });
  });
}

function bindGrantTargets() {
  app.querySelectorAll<HTMLElement>(".card, .dock-avatar-btn").forEach((target) => {
    const sessionEl = target.closest<HTMLElement>("[data-session]");
    if (!sessionEl) return;
    const sessionId = sessionEl.dataset.session!;
    let holdTimer: ReturnType<typeof setTimeout> | null = null;
    let pttActive = false;
    let suppressClick = false;

    const clearHold = () => {
      if (holdTimer) {
        clearTimeout(holdTimer);
        holdTimer = null;
      }
    };

    target.addEventListener("mousedown", (e) => {
      if (e.button !== 0) return;
      suppressClick = false;
      clearHold();
      holdTimer = setTimeout(() => {
        holdTimer = null;
        pttActive = true;
        suppressClick = true;
        send({ type: "ptt", phase: "start", sessionId });
      }, HOLD_MS);
    });

    const endHold = () => {
      clearHold();
      if (pttActive) {
        pttActive = false;
        send({ type: "ptt", phase: "stop", sessionId });
      }
    };

    target.addEventListener("mouseup", endHold);
    target.addEventListener("mouseleave", endHold);

    target.addEventListener("click", () => {
      if (suppressClick) {
        suppressClick = false;
        return;
      }
      send({ type: "grant", sessionId });
    });
  });
}

function bindAvatars() {
  app.querySelectorAll<HTMLImageElement>(".avatar").forEach((img) => {
    img.onerror = () => {
      img.style.display = "none";
      const fallback = img.nextElementSibling as HTMLElement | null;
      if (fallback) fallback.style.display = "flex";
    };
  });
}

function bindControls() {
  app.querySelectorAll<HTMLButtonElement>("[data-action]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const action = btn.dataset.action;
      if (action === "pause") send({ type: "pause" });
      else if (action === "stop") send({ type: "stop" });
      else if (action === "replay") send({ type: "replay" });
    });
  });
}

function armKill(sessionId: string) {
  const existing = killArmed.get(sessionId);
  if (existing) clearTimeout(existing);
  const timer = setTimeout(() => {
    killArmed.delete(sessionId);
    render();
  }, KILL_ARM_MS);
  killArmed.set(sessionId, timer);
}

function bindHoverActions() {
  app.querySelectorAll<HTMLButtonElement>("[data-hover-action]").forEach((btn) => {
    const sessionEl = btn.closest<HTMLElement>("[data-session]");
    if (!sessionEl) return;
    const sessionId = sessionEl.dataset.session!;

    btn.addEventListener("mousedown", (e) => e.stopPropagation());
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      if (btn.disabled) return;

      const action = btn.dataset.hoverAction;
      if (action === "focus") {
        send({ type: "focus_terminal", sessionId });
      } else if (action === "status") {
        send({ type: "status_say", sessionId });
      } else if (action === "kill") {
        if (killArmed.has(sessionId)) {
          const timer = killArmed.get(sessionId)!;
          clearTimeout(timer);
          killArmed.delete(sessionId);
          send({ type: "kill_team", sessionId });
        } else {
          armKill(sessionId);
          render();
        }
      }
    });
  });
}

function bindCards() {
  bindGrantTargets();
}

function handleMessage(raw: string) {
  let msg: { type: string; agents?: AgentView[]; code?: string; sessionId?: string };
  try {
    msg = JSON.parse(raw);
  } catch {
    return;
  }

  if (msg.type === "snapshot" && Array.isArray(msg.agents)) {
    agents = msg.agents;
    staleSessions.clear();
    for (const sid of killArmed.keys()) {
      if (!agents.some((a) => a.sessionId === sid)) {
        const t = killArmed.get(sid);
        if (t) clearTimeout(t);
        killArmed.delete(sid);
      }
    }
    render();
    if (dockMode) void enterDockMode();
    return;
  }

  if (msg.type === "error" && msg.code === "stale_session" && msg.sessionId) {
    staleSessions.add(msg.sessionId);
    render();
  }
}

async function connect() {
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    return;
  }

  let config: WsConfig;
  try {
    config = await invoke<WsConfig>("ws_token");
  } catch (err) {
    console.error("ws_token failed:", err);
    setConnected(false);
    scheduleReconnect();
    return;
  }

  const url = `ws://127.0.0.1:${config.port}/?token=${encodeURIComponent(config.token)}`;
  ws = new WebSocket(url);

  ws.onopen = () => setConnected(true);
  ws.onclose = () => {
    setConnected(false);
    ws = null;
    scheduleReconnect();
  };
  ws.onerror = () => {
    setConnected(false);
  };
  ws.onmessage = (ev) => handleMessage(String(ev.data));
}

render();
connect();
