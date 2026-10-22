// The state the stage animates and the scripted steps. Every reducer follows
// the matching dispatcher in Sources/ouch/Tiling/Manager.

import {
  LAYOUT_TITLE,
  type Direction,
  type LayoutName,
  type Rect,
  cycleLayout,
  frames,
  neighbor,
} from "./layout";

export type Hue = "sky" | "lemon" | "magenta" | "lime";
export const HUES: Hue[] = ["sky", "lemon", "magenta", "lime"];

export const WINDOWS: Record<Hue, { app: string; color: string }> = {
  sky: { app: "Terminal", color: "#1FAFFF" },
  lemon: { app: "Safari", color: "#FFEA14" },
  magenta: { app: "Finder", color: "#FF4AD8" },
  lime: { app: "Notes", color: "#9DFF1F" },
};

export type Desktop = { order: Hue[]; layout: LayoutName; ratio: number; zoomed: Hue | null };
export type State = { desktops: Desktop[]; current: number; focused: Hue };

// The layout runs on a 16:10 screen, like a Mac display. Only the aspect matters:
// frames come back as fractions of this rect.
export const SCREEN: Rect = { x: 0, y: 0, w: 1600, h: 1000 };

export const START: State = {
  desktops: [
    { order: ["sky", "lemon", "magenta", "lime"], layout: "tall", ratio: 0.6, zoomed: null },
  ],
  current: 0,
  focused: "sky",
};

export type Slot = { rect: Rect; desktop: number; z: number };

// WindowManager.layoutTargets: each window gets its slot. A zoomed window
// takes the whole usable rect and stays on top.
export function place(state: State): Map<Hue, Slot> {
  const out = new Map<Hue, Slot>();
  state.desktops.forEach((d, di) => {
    const fr = frames(d.layout, d.order.length, SCREEN, d.ratio);
    d.order.forEach((hue, i) => {
      const zoomed = d.zoomed === hue;
      const z = hue === state.focused ? 20 : d.order.length - i;
      out.set(hue, { rect: zoomed ? SCREEN : fr[i], desktop: di, z: zoomed ? 30 : z });
    });
  });
  return out;
}

function clone(s: State): State {
  return {
    ...s,
    desktops: s.desktops.map((d) => ({ ...d, order: [...d.order] })),
  };
}

function desktopOf(s: State, hue: Hue): number {
  return s.desktops.findIndex((d) => d.order.includes(hue));
}

// movewindow l|d|u|r: swap places with the directional neighbour, then retile.
export function movewindow(s: State, dir: Direction): State {
  const n = clone(s);
  const di = desktopOf(n, n.focused);
  const d = n.desktops[di];
  const fr = frames(d.layout, d.order.length, SCREEN, d.ratio);
  const items = d.order.map((id, i) => ({ id, frame: fr[i] }));
  const from = items[d.order.indexOf(n.focused)];
  const target = neighbor(from, items, dir);
  if (target === null) return s;
  const a = d.order.indexOf(n.focused);
  const b = d.order.indexOf(target);
  [d.order[a], d.order[b]] = [d.order[b], d.order[a]];
  return n;
}

// fullscreen: toggleZoom on the focused window.
export function fullscreen(s: State): State {
  const n = clone(s);
  const d = n.desktops[desktopOf(n, n.focused)];
  d.zoomed = d.zoomed === n.focused ? null : n.focused;
  return n;
}

// workspace N: show that Desktop. A missing Desktop is created on demand.
export function workspace(s: State, index: number): State {
  const n = clone(s);
  while (n.desktops.length <= index) {
    n.desktops.push({ order: [], layout: "tall", ratio: 0.5, zoomed: null });
  }
  n.current = index;
  const d = n.desktops[index];
  if (!d.order.includes(n.focused) && d.order.length > 0) n.focused = d.order[0];
  return n;
}

// movetoworkspace N: move the focused window there and follow it.
export function movetoworkspace(s: State, index: number): State {
  const n = workspace(clone(s), index);
  const from = n.desktops[desktopOf(n, s.focused)];
  from.order = from.order.filter((h) => h !== s.focused);
  if (from.zoomed === s.focused) from.zoomed = null;
  n.desktops[index].order.push(s.focused);
  n.focused = s.focused;
  return n;
}

// cyclelayout next|prev and layout <name>: setLayout clears zoom.
export function cyclelayout(s: State, delta: 1 | -1): State {
  const n = clone(s);
  const d = n.desktops[n.current];
  d.layout = cycleLayout(d.layout, delta);
  d.zoomed = null;
  return n;
}

export function setLayout(s: State, layout: LayoutName): State {
  const n = clone(s);
  const d = n.desktops[n.current];
  d.layout = layout;
  d.zoomed = null;
  return n;
}

// layoutmsg swapwithmaster: swap with index 0, or with index 1 when already main.
export function swapwithmaster(s: State): State {
  const n = clone(s);
  const d = n.desktops[desktopOf(n, n.focused)];
  const i = d.order.indexOf(n.focused);
  const j = i === 0 ? 1 : 0;
  if (d.order.length < 2) return s;
  [d.order[i], d.order[j]] = [d.order[j], d.order[i]];
  return n;
}

// Opening a template: every saved window comes to the current Desktop, first
// in order, the display gets the saved layout and ratio, and zoom is cleared.
export function openTemplate(
  s: State,
  template: { order: Hue[]; layout: LayoutName; ratio: number },
): State {
  const n = clone(s);
  for (const d of n.desktops) {
    d.order = d.order.filter((h) => !template.order.includes(h));
    if (d.zoomed && template.order.includes(d.zoomed)) d.zoomed = null;
  }
  const d = n.desktops[n.current];
  d.order = [...template.order, ...d.order];
  d.layout = template.layout;
  d.ratio = Math.min(0.9, Math.max(0.1, template.ratio));
  d.zoomed = null;
  n.focused = template.order[0];
  return n;
}

// Overview, movewindow up|down: reorder the window inside its lane by one.
export function reorder(s: State, delta: 1 | -1): State {
  const n = clone(s);
  const d = n.desktops[desktopOf(n, n.focused)];
  const i = d.order.indexOf(n.focused);
  const j = i + delta;
  if (j < 0 || j >= d.order.length) return s;
  [d.order[i], d.order[j]] = [d.order[j], d.order[i]];
  return n;
}

export const TEMPLATE = { name: "Writing", order: HUES, layout: "tall" as LayoutName, ratio: 0.6 };

export type Key = { id: string; caps: string[] };

export type Fx =
  | { kind: "mode"; on: boolean }
  | { kind: "hud"; text: string; thumb: boolean }
  | { kind: "menu"; open: boolean }
  | { kind: "overview"; open: boolean }
  | { kind: "overview-plan" }
  | { kind: "type"; text: string };

export type Action = {
  key?: string;
  hold?: number;
  fx?: Fx[];
  apply?: (s: State) => State;
  plan?: boolean;
};

export type Step = {
  id: string;
  title: string;
  body: string;
  keys: Key[];
  actions: Action[];
};

const hudLayout = (s: State) => LAYOUT_TITLE[s.desktops[s.current].layout];

export const STEPS: Step[] = [
  {
    id: "mode",
    title: "Window mode",
    body: "Press ⌘ Caps Lock once, then single keys do the work, like Vim. Shift with H J K L moves the window. F fills the screen. Esc leaves.",
    keys: [
      { id: "cmdcaps", caps: ["⌘", "⇪"] },
      { id: "shiftl", caps: ["⇧", "L"] },
      { id: "shifth", caps: ["⇧", "H"] },
      { id: "f", caps: ["F"] },
    ],
    actions: [
      { key: "cmdcaps", fx: [{ kind: "mode", on: true }], hold: 1.1 },
      { key: "shiftl", apply: (s) => movewindow(s, "r") },
      { key: "shifth", apply: (s) => movewindow(s, "l") },
      { key: "f", apply: fullscreen },
      { key: "f", apply: fullscreen },
    ],
  },
  {
    id: "workspaces",
    title: "Workspaces are Desktops",
    body: "Each workspace is a real macOS Desktop. 1 to 0 goes there. Shift and a number takes the window with you.",
    keys: [
      { id: "shift2", caps: ["⇧", "2"] },
      { id: "one", caps: ["1"] },
    ],
    actions: [
      {
        key: "shift2",
        apply: (s) => movetoworkspace(s, 1),
        fx: [{ kind: "hud", text: "2", thumb: true }],
        hold: 1.4,
      },
      { key: "one", apply: (s) => workspace(s, 0), fx: [{ kind: "hud", text: "1", thumb: true }] },
    ],
  },
  {
    id: "layouts",
    title: "Layouts",
    body: "Every workspace has its own layout. N and P cycle through tall, wide, fullscreen, binary space partitioning and column. Comma and period resize the main window.",
    keys: [{ id: "n", caps: ["N"] }],
    actions: [1, 2, 3, 4, 5].map(() => ({
      key: "n",
      apply: (s: State) => cyclelayout(s, 1),
      fx: [{ kind: "hud", text: "", thumb: true }],
      hold: 1.2,
    })),
  },
  {
    id: "templates",
    title: "Save workspaces",
    body: "Tap ⌘ in window mode for your saved workspaces. S saves the current one with its apps. 1 to 9 opens one, and every window comes back.",
    keys: [
      { id: "cmd", caps: ["⌘"] },
      { id: "t1", caps: ["1"] },
      { id: "esc", caps: ["esc"] },
    ],
    actions: [
      { key: "cmd", fx: [{ kind: "menu", open: true }], hold: 1.3 },
      {
        key: "t1",
        fx: [
          { kind: "menu", open: false },
          { kind: "hud", text: `Opened ${TEMPLATE.name}.`, thumb: false },
        ],
        apply: (s) => openTemplate(s, TEMPLATE),
        hold: 1.4,
      },
      { key: "esc", fx: [{ kind: "mode", on: false }] },
    ],
  },
  {
    id: "overview",
    title: "Overview",
    body: "⌥ O shows every workspace as a lane. Move windows between lanes with the same keys. Press Return and CatWM lays it all out at once.",
    keys: [
      { id: "alto", caps: ["⌥", "O"] },
      { id: "shiftj", caps: ["⇧", "J"] },
      { id: "ret", caps: ["↩"] },
    ],
    actions: [
      { key: "alto", fx: [{ kind: "overview", open: true }], hold: 1.3 },
      {
        key: "shiftj",
        apply: (s) => reorder(s, 1),
        plan: true,
        fx: [{ kind: "overview-plan" }],
        hold: 1.2,
      },
      // Done applies the plan: the windows move only now.
      { key: "ret", apply: (s) => reorder(s, 1), fx: [{ kind: "overview", open: false }] },
    ],
  },
  {
    id: "cli",
    title: "A CLI for scripts and agents",
    body: "Every bind is a dispatcher, and the CLI runs the same ones.",
    keys: [],
    actions: [
      {
        fx: [{ kind: "type", text: "ouch dispatch layoutmsg swapwithmaster" }],
        apply: swapwithmaster,
        hold: 1.4,
      },
      {
        fx: [
          { kind: "type", text: "ouch dispatch cyclelayout next" },
          { kind: "hud", text: "", thumb: true },
        ],
        apply: (s) => cyclelayout(s, 1),
        hold: 1.4,
      },
      {
        fx: [
          { kind: "type", text: "ouch dispatch layout tall" },
          { kind: "hud", text: "", thumb: true },
        ],
        apply: (s) => setLayout(s, "tall"),
        hold: 1.4,
      },
    ],
  },
];

// A HUD with empty text shows the layout title after the action.
export function hudText(fx: Fx, after: State): string {
  if (fx.kind !== "hud") return "";
  return fx.text === "" ? hudLayout(after) : fx.text;
}
