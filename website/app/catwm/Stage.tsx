import gsap from "gsap";
import { type ReactNode, useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

import { type Rect } from "./layout";
import {
  ATTRACT,
  HUES,
  type Hue,
  KEYS,
  type KeyId,
  SCREEN,
  START,
  type State,
  WINDOWS,
  focus,
  place,
} from "./script";
import { usePulse } from "./usePulse";
import { PulseVeil } from "./PulseVeil";

// Animator defaults: animation-duration 0.18, animation-curve ease-out (cubic).
const MOVE = { duration: 0.18, ease: "power3.out" } as const;

// Every in-screen component is drawn in points for a 1440 pt display and scaled by --s.
const SCREEN_PT = 1440;

const pct = (v: number) => `${v}%`;

function slotStyle(rect: Rect, tilt: number, z: number) {
  return {
    left: pct((rect.x / SCREEN.w) * 100),
    top: pct((rect.y / SCREEN.h) * 100),
    width: pct((rect.w / SCREEN.w) * 100),
    height: pct((rect.h / SCREEN.h) * 100),
    rotation: tilt,
    zIndex: z,
  };
}

type Props = { hero: ReactNode };

export function Stage({ hero }: Props) {
  const root = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<State>(START);
  const stateRef = useRef(state);
  const first = useRef(true);
  const attract = useRef<{ stopped: boolean; timer: number }>({ stopped: false, timer: 0 });
  const stillRef = useRef(false);

  const press = useCallback((id: KeyId) => {
    const key = KEYS.find((k) => k.id === id);
    if (!key) return;
    const next = key.apply(stateRef.current);
    stateRef.current = next;
    setState(next);
  }, []);

  const focusWindow = useCallback((hue: Hue) => {
    const next = focus(stateRef.current, hue);
    stateRef.current = next;
    setState(next);
  }, []);

  const stopAttract = useCallback(() => {
    attract.current.stopped = true;
    window.clearTimeout(attract.current.timer);
  }, []);

  // The windows move the way the animator moves them, from wherever they are.
  useLayoutEffect(() => {
    const el = root.current;
    if (!el) return;
    const slots = place(state);
    const still = stillRef.current;
    for (const hue of HUES) {
      const slot = slots.get(hue)!;
      const slab = el.querySelector<HTMLElement>(`[data-slab="${hue}"]`)!;
      const { zIndex, ...geometry } = slotStyle(slot.rect, slot.tilt, slot.z);
      gsap.set(slab, { zIndex });
      if (first.current || still) gsap.set(slab, geometry);
      else gsap.to(slab, { ...geometry, ...MOVE, overwrite: "auto" });
    }

    first.current = false;
  }, [state]);

  useEffect(() => {
    const el = root.current;
    if (!el) return;
    stillRef.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const scale = () =>
      el.style.setProperty("--s", String(Math.min(1, el.clientWidth / SCREEN_PT)));
    scale();
    window.addEventListener("resize", scale);

    // Until the visitor presses a key, the page shows what the keys do.
    let i = 0;
    const tick = () => {
      if (attract.current.stopped) return;
      if (document.hidden) {
        attract.current.timer = window.setTimeout(tick, 1000);
        return;
      }
      press(ATTRACT[i].key);
      i = (i + 1) % ATTRACT.length;
      attract.current.timer = window.setTimeout(tick, ATTRACT[i].after * 1000);
    };
    if (!stillRef.current) attract.current.timer = window.setTimeout(tick, ATTRACT[0].after * 1000);

    return () => {
      window.removeEventListener("resize", scale);
      window.clearTimeout(attract.current.timer);
    };
  }, [press, stopAttract]);

  usePulse(root, "#000", "#fff");

  const startSlots = place(START);

  return (
    <div ref={root} className="stage">
      <div className="screen">
        {HUES.map((hue) => {
          const slot = startSlots.get(hue)!;
          const { rotation, ...style } = slotStyle(slot.rect, slot.tilt, slot.z);
          return (
            <div
              key={hue}
              className="slab"
              data-slab={hue}
              data-focused={state.focused === hue || undefined}
              style={{ ...style, transform: `rotate(${rotation}deg)` }}
              onPointerEnter={(e) => e.pointerType === "mouse" && focusWindow(hue)}
              onClick={() => {
                stopAttract();
                focusWindow(hue);
              }}
            >
              <div className="slab__face" style={{ background: WINDOWS[hue].color }} />
            </div>
          );
        })}
      </div>

      <PulseVeil />
      <div className="hero">{hero}</div>
    </div>
  );
}
