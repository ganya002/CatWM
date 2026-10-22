// LayoutThumbnail, the layout drawing the HUD shows, in points. A port of the
// Swift view with the same name.

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
