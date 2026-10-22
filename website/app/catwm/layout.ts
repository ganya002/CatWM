// A port of Sources/ouch/Tiling/Layout/Layout.swift and
// Sources/ouch/Tiling/Navigation/Motion/MotionResolver.swift.
// The page animates only what these functions say.

export type Rect = { x: number; y: number; w: number; h: number };
export type LayoutName = "tall" | "wide" | "fullscreen" | "bsp" | "column";

// Config.layouts default: the order `n` and `p` cycle through.
export const LAYOUT_CYCLE: LayoutName[] = ["tall", "wide", "fullscreen", "bsp", "column"];

// Layout.title, shown by the HUD on a layout change.
export const LAYOUT_TITLE: Record<LayoutName, string> = {
  tall: "Tall",
  wide: "Wide",
  fullscreen: "Fullscreen",
  bsp: "Binary Space Partitioning",
  column: "Column",
};

export function rows(r: Rect, n: number): Rect[] {
  const h = r.h / n;
  return Array.from({ length: n }, (_, i) => ({ x: r.x, y: r.y + h * i, w: r.w, h }));
}

export function columns(r: Rect, n: number): Rect[] {
  const w = r.w / n;
  return Array.from({ length: n }, (_, i) => ({ x: r.x + w * i, y: r.y, w, h: r.h }));
}

// CGRect.divided(atDistance:from:). The origin is top-left, so minY is the top.
function divided(r: Rect, amount: number, edge: "minX" | "maxX" | "minY"): [Rect, Rect] {
  switch (edge) {
    case "minX":
      return [
        { x: r.x, y: r.y, w: amount, h: r.h },
        { x: r.x + amount, y: r.y, w: r.w - amount, h: r.h },
      ];
    case "maxX":
      return [
        { x: r.x + r.w - amount, y: r.y, w: amount, h: r.h },
        { x: r.x, y: r.y, w: r.w - amount, h: r.h },
      ];
    case "minY":
      return [
        { x: r.x, y: r.y, w: r.w, h: amount },
        { x: r.x, y: r.y + amount, w: r.w, h: r.h - amount },
      ];
  }
}

// Layout.frames(count:in:ratio:mainCount:)
export function frames(
  layout: LayoutName,
  count: number,
  rect: Rect,
  ratio: number,
  mainCount = 1,
): Rect[] {
  if (count <= 0) return [];
  const mains = Math.max(1, Math.min(mainCount, count));
  switch (layout) {
    case "fullscreen":
      return Array.from({ length: count }, () => ({ ...rect }));
    case "column":
      return columns(rect, count);
    case "tall": {
      if (count <= mains) return rows(rect, count);
      const [main, rest] = divided(rect, rect.w * ratio, "minX");
      return [...rows(main, mains), ...rows(rest, count - mains)];
    }
    case "wide": {
      if (count <= mains) return columns(rect, count);
      const [main, rest] = divided(rect, rect.h * ratio, "minY");
      return [...columns(main, mains), ...columns(rest, count - mains)];
    }
    case "bsp": {
      const out: Rect[] = [];
      let rest = rect;
      for (let i = 0; i < count; i++) {
        if (i === count - 1) {
          out.push(rest);
          break;
        }
        const vertical = rest.w >= rest.h;
        const amount = (vertical ? rest.w : rest.h) * (i === 0 ? ratio : 0.5);
        const [slice, remainder] = divided(rest, amount, vertical ? "minX" : "minY");
        out.push(slice);
        rest = remainder;
      }
      return out;
    }
  }
}

// cyclelayout next / prev wraps around the config list.
export function cycleLayout(current: LayoutName, delta: 1 | -1): LayoutName {
  const n = LAYOUT_CYCLE.length;
  const i = Math.max(0, LAYOUT_CYCLE.indexOf(current));
  return LAYOUT_CYCLE[(((i + delta) % n) + n) % n];
}

export type Direction = "l" | "r" | "u" | "d";

type Relation = { along: number; across: number; overlaps: boolean; edge: number };

function relation(from: Rect, other: Rect, dir: Direction): Relation {
  const dx = other.x + other.w / 2 - (from.x + from.w / 2);
  const dy = other.y + other.h / 2 - (from.y + from.h / 2);
  const rowsOverlap = other.y < from.y + from.h && other.y + other.h > from.y;
  const colsOverlap = other.x < from.x + from.w && other.x + other.w > from.x;
  switch (dir) {
    case "l":
      return { along: -dx, across: dy, overlaps: rowsOverlap, edge: from.x - (other.x + other.w) };
    case "r":
      return { along: dx, across: dy, overlaps: rowsOverlap, edge: other.x - (from.x + from.w) };
    case "u":
      return { along: -dy, across: dx, overlaps: colsOverlap, edge: from.y - (other.y + other.h) };
    case "d":
      return { along: dy, across: dx, overlaps: colsOverlap, edge: other.y - (from.y + from.h) };
  }
}

// MotionResolver.neighbor on one display, with no focus stamps: the nearest
// adjacent window with the best score wins.
export function neighbor<T>(
  from: { id: T; frame: Rect },
  candidates: { id: T; frame: Rect }[],
  dir: Direction,
): T | null {
  const scored: { id: T; score: number; edge: number }[] = [];
  for (const other of candidates) {
    if (other.id === from.id) continue;
    const g = relation(from.frame, other.frame, dir);
    if (g.along <= 1 || !g.overlaps) continue;
    scored.push({
      id: other.id,
      score: g.along + Math.abs(g.across) * 2,
      edge: Math.max(0, g.edge),
    });
  }
  if (scored.length === 0) return null;
  const nearest = Math.min(...scored.map((s) => s.edge));
  const adjacent = scored.filter((s) => s.edge <= nearest + 2);
  return adjacent.reduce((a, b) => (b.score < a.score ? b : a)).id;
}
