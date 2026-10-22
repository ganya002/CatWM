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
  hudTitle,
  place,
} from "./script";
import { layoutThumb } from "./thumbs";

// Animator defaults: animation-duration 0.18, animation-curve ease-out (cubic).
const MOVE = { duration: 0.18, ease: "power3.out" } as const;

// Palette.catwm, dark.
const ACCENT = "#1FAFFF";
const TINT = "#3A3A3A";
const RAISED = "#1C1C1C";

// Every in-screen component is drawn in points for a 1440 pt display and scaled by --s.
const SCREEN_PT = 1440;

const HUD_THUMB = layoutThumb("tall", 120, 75);

const GROUPS: { keys: KeyId[]; label: string }[] = [
  { keys: ["n"], label: "Layout" },
  { keys: ["h", "j", "k", "l"], label: "Move" },
  { keys: ["f"], label: "Fill" },
  { keys: ["t"], label: "Tiling" },
];

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

function keyFromEvent(e: KeyboardEvent): KeyId | null {
  if (e.metaKey || e.ctrlKey || e.altKey) return null;
  const k = e.key.toLowerCase();
  if (e.shiftKey) return k === "h" || k === "j" || k === "k" || k === "l" || k === "t" ? k : null;
  return k === "n" || k === "f" ? k : null;
}

type Props = { hero: ReactNode };

export function Stage({ hero }: Props) {
  const root = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<State>(START);
  const stateRef = useRef(state);
  const first = useRef(true);
  const shown = useRef(START);
  const attract = useRef<{ stopped: boolean; timer: number }>({ stopped: false, timer: 0 });
  const stillRef = useRef(false);

  const press = useCallback((id: KeyId) => {
    const el = root.current;
    if (!el) return;
    const key = KEYS.find((k) => k.id === id);
    if (!key) return;
    const cap = el.querySelector<HTMLElement>(`[data-key="${id}"] .key:last-child`);
    if (cap && !stillRef.current) {
      // Kbd pressed: accent fill, onAccent text, sunk 2 pt, Motion.fade.
      gsap
        .timeline()
        .to(cap, {
          backgroundColor: ACCENT,
          color: "#000",
          y: 2,
          duration: 0.12,
          ease: "power2.out",
        })
        .to(
          cap,
          { backgroundColor: RAISED, color: "#fff", y: 0, duration: 0.12, ease: "power2.out" },
          0.22,
        );
    }
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

    const layoutChanged =
      shown.current.tiling !== state.tiling || shown.current.layout !== state.layout;
    shown.current = state;
    if (!first.current && layoutChanged) {
      // HUDView: the layout thumbnail over the title, popping from 0.9 with a
      // spring, gone after 1 s (0.8 s without a thumbnail) with a 0.25 s fade.
      const hud = el.querySelector<HTMLElement>("[data-hud]")!;
      const label = el.querySelector<HTMLElement>("[data-hud-text]")!;
      const thumb = el.querySelector<HTMLElement>("[data-hud-thumb]")!;
      const panes = el.querySelectorAll<SVGRectElement>("[data-hud-pane]");
      label.textContent = hudTitle(state);
      thumb.style.display = state.tiling ? "block" : "none";
      hud.dataset.plain = state.tiling ? "0" : "1";
      if (state.tiling) {
        layoutThumb(state.layout, 120, 75).panes.forEach((r, i) => {
          gsap.set(panes[i], { attr: { x: r.x, y: r.y, width: r.w, height: r.h } });
        });
      }
      gsap
        .timeline({ overwrite: true })
        .set(hud, { autoAlpha: 1 })
        .fromTo(
          hud,
          { scale: 0.9 },
          { scale: 1, duration: still ? 0 : 0.45, ease: "back.out(1.7)" },
        )
        .to(
          hud,
          { autoAlpha: 0, duration: still ? 0 : 0.25, ease: "power1.inOut" },
          state.tiling ? 1 : 0.8,
        );
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

    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return;
      const id = keyFromEvent(e);
      if (!id) return;
      e.preventDefault();
      stopAttract();
      press(id);
    };
    window.addEventListener("keydown", onKey);

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

    // The pulse: a circle grows out of the install button until it covers the
    // screen, dark on the slow cycle and light on a click, then fades back.
    // The button sits above it, so it is the one thing the pulse leaves alone.
    const veil = el.querySelector<HTMLElement>("[data-pulse]");
    const cta = el.querySelector<HTMLElement>("[data-cta]");
    let pulseTimer = 0;
    let onScreen = true;
    let running: gsap.core.Timeline | null = null;
    const pulse = (light: boolean) => {
      if (!veil || !cta) return;
      const stage = el.getBoundingClientRect();
      const b = cta.getBoundingClientRect();
      const x = b.left + b.width / 2 - stage.left;
      const y = b.top + b.height / 2 - stage.top;
      const reach = Math.hypot(Math.max(x, stage.width - x), Math.max(y, stage.height - y));
      veil.style.background = light ? "#fff" : "#000";
      running?.kill();
      cta.classList.add("is-lit");
      running = gsap
        .timeline({ onComplete: () => cta.classList.remove("is-lit") })
        .fromTo(
          veil,
          { clipPath: `circle(${b.width * 0.5}px at ${x}px ${y}px)`, opacity: 1 },
          { clipPath: `circle(${reach}px at ${x}px ${y}px)`, duration: 1.3, ease: "power2.out" },
          0,
        )
        .fromTo(cta, { "--spin": "0deg" }, { "--spin": "720deg", duration: 2.8, ease: "none" }, 0)
        .to(veil, { opacity: 0, duration: 0.9, ease: "power1.inOut" }, 1.8);
    };
    const cycle = () => {
      if (onScreen && !document.hidden) pulse(false);
      pulseTimer = window.setTimeout(cycle, 6500);
    };
    const onCta = () => {
      window.clearTimeout(pulseTimer);
      pulseTimer = window.setTimeout(cycle, 6500);
      pulse(true);
    };
    const io = new IntersectionObserver(([entry]) => {
      onScreen = entry.isIntersecting;
    });
    io.observe(el);
    cta?.addEventListener("click", onCta);
    if (!stillRef.current) pulseTimer = window.setTimeout(cycle, 1800);

    return () => {
      window.removeEventListener("resize", scale);
      window.removeEventListener("keydown", onKey);
      window.clearTimeout(attract.current.timer);
      window.clearTimeout(pulseTimer);
      io.disconnect();
      cta?.removeEventListener("click", onCta);
      running?.kill();
    };
  }, [press, stopAttract]);

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

      <div className="hud" data-hud data-plain="0" aria-hidden="true">
        <svg className="hud__thumb" data-hud-thumb viewBox="0 0 120 75">
          {HUD_THUMB.panes.map((r, i) => (
            <rect
              key={i}
              data-hud-pane
              x={r.x}
              y={r.y}
              width={r.w}
              height={r.h}
              rx={HUD_THUMB.radius}
              fill={i === 0 ? ACCENT : TINT}
            />
          ))}
        </svg>
        <span className="hud__text" data-hud-text />
      </div>

      <div className="pulse" data-pulse aria-hidden="true" />
      <div className="hero">{hero}</div>

      <div className="keys" aria-label="Try the keys">
        {GROUPS.map((group) => (
          <div key={group.label} className="keys__group">
            {group.keys.map((id) => {
              const key = KEYS.find((k) => k.id === id)!;
              return (
                <button
                  key={id}
                  type="button"
                  className="chord"
                  data-key={id}
                  aria-label={`${key.caps.join(" ")} ${group.label}`}
                  onClick={() => {
                    stopAttract();
                    press(id);
                  }}
                >
                  {key.caps.map((cap, i) => (
                    <kbd key={i} className="key">
                      {cap}
                    </kbd>
                  ))}
                </button>
              );
            })}
            <span className="keys__label">{group.label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
