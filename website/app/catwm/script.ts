// The state the stage animates and the reducers behind each key. Every reducer
// follows the matching dispatcher in Sources/ouch/Tiling/Manager.

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

// The layout runs on a 16:10 screen, like a Mac display. Only the aspect matters:
// frames come back as fractions of this rect.
export const SCREEN: Rect = { x: 0, y: 0, w: 1600, h: 1000 };

export type State = {
  order: Hue[];
  layout: LayoutName;
  ratio: number;
  zoomed: Hue | null;
  focused: Hue;
  // toggletiling off: the windows lie where the apps left them.
  tiling: boolean;
};

// Before CatWM: four windows left where they were opened.
export const PILE: Record<Hue, Rect & { tilt: number }> = {
  sky: { x: 110, y: 120, w: 820, h: 600, tilt: -2.5 },
  lemon: { x: 760, y: 70, w: 700, h: 470, tilt: 2 },
  magenta: { x: 560, y: 450, w: 640, h: 480, tilt: -1.5 },
  lime: { x: 1020, y: 400, w: 500, h: 520, tilt: 3 },
};

export const START: State = {
  order: HUES,
  layout: "tall",
  ratio: 0.6,
  zoomed: null,
  focused: "sky",
  tiling: false,
};

export type Slot = { rect: Rect; tilt: number; z: number };

// WindowManager.layoutTargets: each window gets its slot. A zoomed window
// takes the whole screen and stays on top. With tiling off, the pile.
export function place(state: State): Map<Hue, Slot> {
  const out = new Map<Hue, Slot>();
  if (!state.tiling) {
    HUES.forEach((hue, i) => {
      const { tilt, ...rect } = PILE[hue];
      out.set(hue, { rect, tilt, z: hue === state.focused ? 10 : i + 1 });
    });
    return out;
  }
  const fr = frames(state.layout, state.order.length, SCREEN, state.ratio);
  state.order.forEach((hue, i) => {
    const zoomed = state.zoomed === hue;
    const z = hue === state.focused ? 20 : state.order.length - i;
    out.set(hue, { rect: zoomed ? SCREEN : fr[i], tilt: 0, z: zoomed ? 30 : z });
  });
  return out;
}

// focus-follows-mouse: the window under the pointer takes focus.
export function focus(s: State, hue: Hue): State {
  return s.focused === hue ? s : { ...s, focused: hue };
}

// movewindow l|d|u|r: swap places with the directional neighbour, then retile.
export function movewindow(s: State, dir: Direction): State {
  if (!s.tiling || s.zoomed) return s;
  const fr = frames(s.layout, s.order.length, SCREEN, s.ratio);
  const items = s.order.map((id, i) => ({ id, frame: fr[i] }));
  const from = items[s.order.indexOf(s.focused)];
  const target = neighbor(from, items, dir);
  if (target === null) return s;
  const order = [...s.order];
  const a = order.indexOf(s.focused);
  const b = order.indexOf(target);
  [order[a], order[b]] = [order[b], order[a]];
  return { ...s, order };
}

// fullscreen: toggleZoom on the focused window.
export function fullscreen(s: State): State {
  if (!s.tiling) return s;
  return { ...s, zoomed: s.zoomed === s.focused ? null : s.focused };
}

// cyclelayout next: the first press tiles the pile, later ones cycle the list.
// setLayout clears zoom.
export function cyclelayout(s: State): State {
  if (!s.tiling) return { ...s, tiling: true, layout: "tall", zoomed: null };
  return { ...s, layout: cycleLayout(s.layout, 1), zoomed: null };
}

// toggletiling: back to the pile, or tile again.
export function toggletiling(s: State): State {
  return { ...s, tiling: !s.tiling, zoomed: null };
}

export type KeyId = "n" | "f" | "t" | "h" | "j" | "k" | "l";

export const KEYS: { id: KeyId; caps: string[]; label: string; apply: (s: State) => State }[] = [
  { id: "n", caps: ["N"], label: "Layout", apply: cyclelayout },
  { id: "h", caps: ["⇧", "H"], label: "Move", apply: (s) => movewindow(s, "l") },
  { id: "j", caps: ["⇧", "J"], label: "", apply: (s) => movewindow(s, "d") },
  { id: "k", caps: ["⇧", "K"], label: "", apply: (s) => movewindow(s, "u") },
  { id: "l", caps: ["⇧", "L"], label: "", apply: (s) => movewindow(s, "r") },
  { id: "f", caps: ["F"], label: "Fill", apply: fullscreen },
  { id: "t", caps: ["⇧", "T"], label: "Tiling", apply: toggletiling },
];

// What the page does on its own until the visitor presses a key.
export const ATTRACT: { key: KeyId; after: number }[] = [
  { key: "n", after: 2.6 },
  { key: "l", after: 2.4 },
  { key: "f", after: 2.4 },
  { key: "f", after: 2.2 },
  { key: "n", after: 2.6 },
  { key: "n", after: 2.6 },
  { key: "n", after: 2.6 },
  { key: "n", after: 2.6 },
  { key: "t", after: 3.4 },
];

export function hudTitle(s: State): string {
  return s.tiling ? LAYOUT_TITLE[s.layout] : "Floating";
}
