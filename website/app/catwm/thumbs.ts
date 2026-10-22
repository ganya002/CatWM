// The three layout drawings the app uses, in points: LayoutThumbnail (the HUD
// and the layout picker), SortThumb (an Overview lane) and SortLayoutGlyph
// (the layout pill). Each is a port of the Swift view with the same name.

import { type LayoutName, type Rect, frames } from "./layout";

function grownFrames(
  layout: LayoutName,
  count: number,
  rect: Rect,
  ratio: number,
  gap: number,
): Rect[] {
  const grown = { x: rect.x - gap / 2, y: rect.y - gap / 2, w: rect.w + gap, h: rect.h + gap };
  return frames(layout, count, grown, ratio).map((f) => ({
    x: f.x + gap / 2,
    y: f.y + gap / 2,
    w: f.w - gap,
    h: f.h - gap,
  }));
}

// LayoutThumbnail: four panes, ratio 0.5, no outer margin.
export function layoutThumb(layout: LayoutName, w: number, h: number) {
  const gap = Math.max(1.5, w * 0.035);
  return {
    radius: Math.max(1.5, Math.min(w, h) * 0.05),
    panes: grownFrames(layout, 4, { x: 0, y: 0, w, h }, 0.5, gap),
  };
}

// SortThumb: one pane per window, the lane's ratio, a 4 pt inset and a 3 pt
// gap at 140 wide. Fullscreen cascades the panes by 4 pt steps.
export function sortThumb(
  layout: LayoutName,
  count: number,
  w: number,
  h: number,
  ratio: number,
): Rect[] {
  if (count === 0) return [];
  const scale = w / 140;
  const inset = 4 * scale;
  const gap = 3 * scale;
  const rect = { x: inset, y: inset, w: w - 2 * inset, h: h - 2 * inset };
  if (layout === "fullscreen") {
    const step = 4 * scale;
    const shrink = Math.min(count - 1, 6) * step;
    return Array.from({ length: count }, (_, i) => ({
      x: rect.x + Math.min(i, 6) * step,
      y: rect.y + Math.min(i, 6) * step,
      w: rect.w - shrink,
      h: rect.h - shrink,
    }));
  }
  return grownFrames(layout, count, rect, ratio, gap);
}

// SortLayoutGlyph: 16 by 14, three panes for most layouts.
export function pillGlyph(layout: LayoutName): Rect[] {
  const count = layout === "fullscreen" ? 1 : layout === "bsp" ? 4 : 3;
  const bounds = { x: 1, y: 0.5, w: 14, h: 13 };
  return grownFrames(layout, count, bounds, 0.5, 1.5);
}
