// The feature cards and the scenes their small displays loop through. Frames
// come from the same layout port as the stage.

import { type LayoutName, type Rect, frames } from "./layout";
import { type Hue, WINDOWS } from "./script";

export const DEMO: Rect = { x: 0, y: 0, w: 160, h: 100 };
const PAD = 3;
const GAP = 2.4;

export type Tile = { id: string; rect: Rect; focused: boolean };
export type Scene = { key?: string; typed?: string; shift: number; tiles: Tile[] };

function inset(r: Rect, by: number): Rect {
  return { x: r.x + by, y: r.y + by, w: r.w - 2 * by, h: r.h - 2 * by };
}

function slots(layout: LayoutName, n: number, ratio = 0.55, desktop = 0): Rect[] {
  const screen = inset(DEMO, PAD);
  return frames(layout, n, screen, ratio).map((r) => ({
    ...inset(r, GAP / 2),
    x: inset(r, GAP / 2).x + desktop * DEMO.w,
  }));
}

function tiled(ids: string[], layout: LayoutName, focused: string, desktop = 0): Tile[] {
  const fr = slots(layout, ids.length, 0.55, desktop);
  return ids.map((id, i) => ({ id, rect: fr[i], focused: id === focused }));
}

export type Card = {
  id: string;
  hue: Hue;
  color: string;
  title: string;
  line: string;
  hold: number;
  scenes: Scene[];
};

const ABC = ["a", "b", "c"];
const ABCD = ["a", "b", "c", "d"];

export const CARDS: Card[] = [
  {
    id: "mode",
    hue: "sky",
    color: WINDOWS.sky.color,
    title: "Window mode",
    line: "⌘ Caps Lock once. Then single keys.",
    hold: 1500,
    scenes: [
      { key: "⌘⇪", shift: 0, tiles: tiled(ABC, "tall", "a") },
      { key: "l", shift: 0, tiles: tiled(ABC, "tall", "b") },
      { key: "j", shift: 0, tiles: tiled(ABC, "tall", "c") },
      { key: "h", shift: 0, tiles: tiled(ABC, "tall", "a") },
      { key: "f", shift: 0, tiles: tiled(["a"], "fullscreen", "a") },
      { key: "f", shift: 0, tiles: tiled(ABC, "tall", "a") },
    ],
  },
  {
    id: "workspaces",
    hue: "lemon",
    color: WINDOWS.lemon.color,
    title: "Workspaces",
    line: "Real macOS Desktops. 1 to 0.",
    hold: 2000,
    scenes: [
      {
        key: "1",
        shift: 0,
        tiles: [...tiled(ABC, "tall", "a"), ...tiled(["d", "e"], "column", "d", 1)],
      },
      {
        key: "2",
        shift: 1,
        tiles: [...tiled(ABC, "tall", "a"), ...tiled(["d", "e"], "column", "d", 1)],
      },
    ],
  },
  {
    id: "layouts",
    hue: "magenta",
    color: WINDOWS.magenta.color,
    title: "Layouts",
    line: "N cycles tall, wide, BSP and column.",
    hold: 1700,
    scenes: (["tall", "wide", "bsp", "column"] as LayoutName[]).map((layout) => ({
      key: "n",
      shift: 0,
      tiles: tiled(ABCD, layout, "a"),
    })),
  },
  {
    id: "cli",
    hue: "lime",
    color: WINDOWS.lime.color,
    title: "Scriptable",
    line: "Every bind is a command. The CLI runs the same ones.",
    hold: 2400,
    scenes: [
      { typed: "ouch dispatch layout wide", shift: 0, tiles: tiled(ABCD, "wide", "a") },
      { typed: "ouch dispatch fullscreen", shift: 0, tiles: tiled(["a"], "fullscreen", "a") },
      { typed: "ouch dispatch layout tall", shift: 0, tiles: tiled(ABCD, "tall", "a") },
    ],
  },
];
