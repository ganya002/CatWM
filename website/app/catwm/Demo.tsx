import { type CSSProperties, useEffect, useRef, useState } from "react";

import { type Card, DEMO } from "./cards";

// A small display that loops a card's scenes. The tiles are SVG rects, so a
// move is geometry, not layout. It runs only while on screen.
export function Demo({ card }: { card: Card }) {
  const host = useRef<HTMLDivElement>(null);
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const el = host.current;
    if (!el) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let timer = 0;
    let i = 0;
    const tick = () => {
      i = (i + 1) % card.scenes.length;
      setIndex(i);
      timer = window.setTimeout(tick, card.hold);
    };
    const io = new IntersectionObserver(([entry]) => {
      window.clearTimeout(timer);
      if (entry.isIntersecting) timer = window.setTimeout(tick, card.hold);
    });
    io.observe(el);
    return () => {
      window.clearTimeout(timer);
      io.disconnect();
    };
  }, [card]);

  const scene = card.scenes[index];
  const ids = [...new Set(card.scenes.flatMap((s) => s.tiles.map((t) => t.id)))];
  const last = new Map<string, { rect: typeof DEMO; focused: boolean }>();
  for (const s of card.scenes.slice(0, index + 1)) for (const t of s.tiles) last.set(t.id, t);

  return (
    <div ref={host} className="demo" style={{ "--card": card.color } as CSSProperties}>
      <svg viewBox={`0 0 ${DEMO.w} ${DEMO.h}`} className="demo__svg">
        <g
          className="demo__desktops"
          style={{ transform: `translateX(${-scene.shift * DEMO.w}px)` }}
        >
          {ids.map((id) => {
            const now = scene.tiles.find((t) => t.id === id);
            const tile = now ?? last.get(id);
            if (!tile) return null;
            const style = {
              x: `${tile.rect.x}px`,
              y: `${tile.rect.y}px`,
              width: `${tile.rect.w}px`,
              height: `${tile.rect.h}px`,
              opacity: now ? 1 : 0,
            } as CSSProperties;
            return (
              <rect
                key={id}
                className="demo__tile"
                data-focused={tile.focused || undefined}
                rx={2.6}
                style={style}
              />
            );
          })}
        </g>
      </svg>
      {scene.key && (
        <kbd className="demo__key" key={`${index}-key`}>
          {scene.key}
        </kbd>
      )}
      {scene.typed && (
        <code className="demo__typed" key={`${index}-typed`}>
          <span className="demo__prompt">$ </span>
          {scene.typed}
        </code>
      )}
    </div>
  );
}
