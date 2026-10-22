import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { CustomEase } from "gsap/CustomEase";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { TextPlugin } from "gsap/TextPlugin";
import { type ReactNode, useRef } from "react";

import { Cat } from "./Cat";
import { type LayoutName, type Rect } from "./layout";
import {
  type Fx,
  HUES,
  type Hue,
  SCREEN,
  START,
  STEPS,
  type State,
  TEMPLATE,
  WINDOWS,
  hudText,
  place,
} from "./script";
import { layoutThumb, pillGlyph, sortThumb } from "./thumbs";

// Animator defaults: animation-duration 0.18, animation-curve ease-out (cubic).
const MOVE = { duration: 0.18, ease: "power3.out" } as const;
const HOLD = 0.9;

// Palette.catwm, dark.
const ACCENT = "#1FAFFF";
const TINT = "#3A3A3A";
const THUMB_MAIN = "#2B7AA6";
const RAISED = "#1C1C1C";

// The on-page screen stands for a 1440 pt display. Every component is drawn
// in points and scaled by --s.
const SCREEN_PT = 1440;

const pct = (v: number) => `${v}%`;

function slotStyle(rect: Rect, desktop: number, z: number) {
  return {
    left: pct((rect.x / SCREEN.w) * 100 + desktop * 100),
    top: pct((rect.y / SCREEN.h) * 100),
    width: pct((rect.w / SCREEN.w) * 100),
    height: pct((rect.h / SCREEN.h) * 100),
    zIndex: z,
  };
}

// The state the Overview opens on: every window on Desktop 1, Desktop 2 empty.
const OVERVIEW_STATE: State = {
  desktops: [
    { order: TEMPLATE.order, layout: TEMPLATE.layout, ratio: TEMPLATE.ratio, zoomed: null },
    { order: [], layout: "tall", ratio: 0.5, zoomed: null },
  ],
  current: 0,
  focused: "sky",
};

const HUD_THUMB = layoutThumb("tall", 120, 75);

function paneFill(hue: Hue, index: number, focused: Hue) {
  return hue === focused ? ACCENT : index === 0 ? THUMB_MAIN : TINT;
}

function Glyph({ layout }: { layout: LayoutName }) {
  return (
    <svg className="pill__glyph" viewBox="0 0 16 14" aria-hidden="true">
      {pillGlyph(layout).map((r, i) => (
        <rect key={i} x={r.x} y={r.y} width={r.w} height={r.h} rx={1.4} fill="currentColor" />
      ))}
    </svg>
  );
}

function MenuIcon({ name }: { name: "plus" | "group" | "dim" | "blur" }) {
  switch (name) {
    case "plus":
      return (
        <svg viewBox="0 0 16 16" aria-hidden="true">
          <path
            d="M8 2.5v11M2.5 8h11"
            stroke="currentColor"
            strokeWidth="1.8"
            strokeLinecap="round"
            fill="none"
          />
        </svg>
      );
    case "group":
      return (
        <svg viewBox="0 0 16 16" aria-hidden="true">
          <rect x="1.5" y="2.5" width="6" height="11" rx="1.5" fill="currentColor" />
          <rect x="9" y="2.5" width="5.5" height="5" rx="1.5" fill="currentColor" />
          <rect x="9" y="8.5" width="5.5" height="5" rx="1.5" fill="currentColor" />
        </svg>
      );
    case "dim":
      return (
        <svg viewBox="0 0 16 16" aria-hidden="true">
          <circle cx="8" cy="8" r="6" stroke="currentColor" strokeWidth="1.5" fill="none" />
          <path d="M8 2a6 6 0 0 0 0 12z" fill="currentColor" />
        </svg>
      );
    case "blur":
      return (
        <svg viewBox="0 0 16 16" aria-hidden="true">
          <path
            d="M8 1.5c2.6 3.2 4.5 5.6 4.5 8a4.5 4.5 0 0 1-9 0c0-2.4 1.9-4.8 4.5-8z"
            stroke="currentColor"
            strokeWidth="1.5"
            fill="none"
          />
          <path d="M3.6 9.5h8.8a4.5 4.5 0 0 1-8.8 0z" fill="currentColor" />
        </svg>
      );
  }
}

type Props = { hero: ReactNode };

export function Story({ hero }: Props) {
  const root = useRef<HTMLElement>(null);
  const startSlots = place(START);
  const lane0 = OVERVIEW_STATE.desktops[0];
  const laneThumb = sortThumb(lane0.layout, lane0.order.length, 160, 100, lane0.ratio);

  useGSAP(
    () => {
      gsap.registerPlugin(ScrollTrigger, TextPlugin, CustomEase);
      // Motion.easeOut, timingCurve(0.2, 0.8, 0.2, 1), and the menu's scale-out curve.
      const EASE_OUT = CustomEase.create("catwmOut", "M0,0 C0.2,0.8 0.2,1 1,1");
      const MENU_OUT = CustomEase.create("catwmMenuOut", "M0,0 C0.4,0 1,1 1,1");

      const el = root.current;
      if (!el) return;
      const q = gsap.utils.selector(el);
      const one = (sel: string) => q(sel)[0] as HTMLElement;
      const screen = one("[data-screen]");
      const desktops = one("[data-desktops]");
      const heroEl = one("[data-hero]");
      const nav = one("[data-nav]");
      const hud = one("[data-hud]");
      const hudLabel = one("[data-hud-text]");
      const hudThumb = one("[data-hud-thumb]");
      const hudPanes = q("[data-hud-pane]");
      const cursor = one("[data-cursor]");
      const menu = one("[data-menu]");
      const menuRows = q("[data-menu-row]");
      const overview = one("[data-overview]");
      const term = one("[data-term]");
      const lines = q("[data-stroke=line]") as unknown as SVGPathElement[];
      const heads = q("[data-stroke=head]") as unknown as SVGPathElement[];
      const slab = (hue: Hue) => one(`[data-slab="${hue}"]`);
      const keyEl = (step: string, key: string) => one(`[data-key="${step}:${key}"]`);

      const mm = gsap.matchMedia();
      mm.add(
        {
          wide: "(min-width: 820px)",
          narrow: "(max-width: 819px)",
          reduce: "(prefers-reduced-motion: reduce)",
        },
        (ctx) => {
          const { wide, reduce } = ctx.conditions as { wide: boolean; reduce: boolean };
          const vw = window.innerWidth;
          const vh = window.innerHeight;

          // Where the screen sits once the story starts: a 16:10 display.
          let box: { left: number; top: number; width: number; height: number };
          if (wide) {
            const w = Math.min(vw * 0.58, vh * 0.78 * 1.6);
            box = { left: vw - w - vw * 0.04, top: (vh - w / 1.6) / 2, width: w, height: w / 1.6 };
          } else {
            const w = vw - 32;
            box = { left: 16, top: 72, width: w, height: w / 1.6 };
          }
          el.style.setProperty("--screen-bottom", `${box.top + box.height}px`);
          const s = box.width / SCREEN_PT;
          screen.style.setProperty("--s", String(s));

          // The mode effect, DrawnHalf: a 4 pt stroke whose outer edge sits on
          // the screen edge, from the top centre down each side to the bottom
          // centre. This display has square corners.
          const { width: sw, height: sh } = box;
          const inset = 2 * s;
          const half = (dir: 1 | -1) => {
            const x0 = sw / 2;
            const xe = dir === 1 ? sw - inset : inset;
            return `M ${x0} ${inset} L ${xe} ${inset} L ${xe} ${sh - inset} L ${x0} ${sh - inset}`;
          };
          const svg = one("[data-modefx]") as unknown as SVGSVGElement;
          svg.setAttribute("viewBox", `0 0 ${sw} ${sh}`);
          [...lines, ...heads].forEach((p, i) => p.setAttribute("d", half(i % 2 === 0 ? 1 : -1)));
          lines.forEach((p) => p.setAttribute("stroke-width", String(4 * s)));
          heads.forEach((p) => {
            p.setAttribute("stroke-width", String(14 * s));
            p.style.filter = `blur(${8 * s}px)`;
          });

          // Hero to story: the screen shrinks into place while the lockup leaves.
          const intro = gsap.timeline({
            scrollTrigger: {
              trigger: el,
              start: "top top",
              end: () => `+=${vh * 0.6}`,
              scrub: true,
            },
          });
          intro
            .to(screen, { ...box, "--gap": "6px", "--r": "14px", ease: "none", duration: 1 }, 0)
            .to(heroEl, { autoAlpha: 0, y: -48, ease: "none", duration: 0.45 }, 0)
            .fromTo(nav, { autoAlpha: 0 }, { autoAlpha: 1, ease: "none", duration: 0.3 }, 0.6)
            .fromTo(cursor, { autoAlpha: 0 }, { autoAlpha: 1, ease: "none", duration: 0.3 }, 0.6);

          // One timeline per step, built from the real reducers.
          let state = START;
          const timelines = STEPS.map((step) => {
            const tl = gsap.timeline({ paused: true });
            let t = 0.2;
            for (const action of step.actions) {
              let effectAt = t;
              if (action.key) {
                // Kbd pressed: accent fill, onAccent text, sunk 2 pt, Motion.fade.
                const k = keyEl(step.id, action.key);
                tl.to(
                  k,
                  {
                    backgroundColor: ACCENT,
                    color: "#000000",
                    y: 2,
                    duration: 0.12,
                    ease: EASE_OUT,
                  },
                  t,
                );
                tl.to(
                  k,
                  {
                    backgroundColor: RAISED,
                    color: "#FFFFFF",
                    y: 0,
                    duration: 0.12,
                    ease: EASE_OUT,
                  },
                  t + 0.22,
                );
              }
              for (const fx of action.fx ?? []) {
                if (fx.kind === "type") {
                  tl.set(term, { text: "" }, t);
                  const typing = fx.text.length * 0.035;
                  tl.to(term, { text: fx.text, duration: typing, ease: "none" }, t + 0.05);
                  effectAt = t + 0.05 + typing + 0.3;
                }
              }
              const before = state;
              const after = action.apply ? action.apply(state) : state;
              if (!action.plan) {
                state = after;
                playMove(tl, before, after, effectAt);
              }
              for (const fx of action.fx ?? []) playFx(tl, fx, effectAt, after, before);
              t = effectAt + (action.hold ?? HOLD);
            }
            return tl;
          });

          function playMove(tl: gsap.core.Timeline, before: State, after: State, at: number) {
            if (before === after) return;
            const a = place(before);
            const b = place(after);
            for (const hue of HUES) {
              const was = a.get(hue);
              const now = b.get(hue);
              if (!was || !now) continue;
              const style = slotStyle(now.rect, now.desktop, now.z);
              tl.set(slab(hue), { zIndex: style.zIndex }, at);
              const { zIndex: _z, ...geometry } = style;
              if (was.desktop !== now.desktop) {
                // Spaces.move puts the window on the other Desktop at once.
                tl.set(slab(hue), geometry, at);
              } else {
                tl.to(slab(hue), { ...geometry, ...MOVE }, at);
              }
            }
            if (before.current !== after.current) {
              // NativeDesktopController slides the Desktops with the same timing.
              tl.to(desktops, { xPercent: -after.current * 100, ...MOVE }, at);
            }
          }

          function playFx(tl: gsap.core.Timeline, fx: Fx, at: number, after: State, before: State) {
            switch (fx.kind) {
              case "mode":
                if (fx.on) {
                  // A 0.45 s cubic keyframe draws the stroke. The comet head is
                  // the last 6% of the path, 14 pt wide and blurred 8 pt.
                  tl.set([...lines, ...heads], { opacity: 1 }, at);
                  tl.fromTo(
                    lines,
                    { strokeDashoffset: 1 },
                    { strokeDashoffset: 0, duration: 0.45, ease: "power2.inOut" },
                    at,
                  );
                  tl.fromTo(
                    heads,
                    { strokeDashoffset: 0.06 },
                    { strokeDashoffset: -0.94, duration: 0.45, ease: "power2.inOut" },
                    at,
                  );
                  tl.set(heads, { opacity: 0 }, at + 0.45);
                } else {
                  tl.to(lines, { opacity: 0, duration: 0.25, ease: EASE_OUT }, at);
                }
                return;
              case "hud": {
                // HUDView: the layout thumbnail over the title, shown at once,
                // popping from 0.9 with a spring, gone after 1 s (0.8 s without
                // a thumbnail) with a 0.25 s fade.
                const layout = fx.thumb ? after.desktops[after.current].layout : null;
                tl.set(hudLabel, { text: hudText(fx, after) }, at);
                tl.set(hudThumb, { display: layout ? "block" : "none" }, at);
                tl.set(hud, { attr: { "data-plain": layout ? "0" : "1" } }, at);
                if (layout) {
                  layoutThumb(layout, 120, 75).panes.forEach((r, i) => {
                    tl.set(hudPanes[i], { attr: { x: r.x, y: r.y, width: r.w, height: r.h } }, at);
                  });
                }
                tl.set(hud, { autoAlpha: 1 }, at);
                tl.fromTo(
                  hud,
                  { scale: 0.9 },
                  { scale: 1, duration: 0.45, ease: "back.out(1.7)" },
                  at,
                );
                tl.to(
                  hud,
                  { autoAlpha: 0, duration: 0.25, ease: "power1.inOut" },
                  at + (layout ? 1 : 0.8),
                );
                return;
              }
              case "menu":
                if (fx.open) {
                  // MenuEntrance: fade 0.12, scale 0.12 to 1 with pop, rows
                  // stagger in from 5 pt above.
                  tl.fromTo(
                    menu,
                    { autoAlpha: 0 },
                    { autoAlpha: 1, duration: 0.12, ease: EASE_OUT },
                    at,
                  );
                  tl.fromTo(
                    menu,
                    { scale: 0.12 },
                    { scale: 1, duration: 0.36, ease: "back.out(1.2)" },
                    at,
                  );
                  tl.fromTo(
                    menuRows,
                    { opacity: 0, y: -5 * s },
                    { opacity: 1, y: 0, duration: 0.24, ease: EASE_OUT, stagger: 0.022 },
                    at + 0.06,
                  );
                } else {
                  tl.to(menu, { autoAlpha: 0, duration: 0.12, ease: "power1.in" }, at);
                  tl.to(menu, { scale: 0.12, duration: 0.14, ease: MENU_OUT }, at);
                  tl.to(menuRows, { opacity: 0, duration: 0.08, ease: "power1.in" }, at);
                }
                return;
              case "overview":
                // panel-animation rise: opacity, 22 pt up, scale 0.985 from
                // the bottom, over the animator's 0.18 s ease-out.
                if (fx.open) {
                  tl.fromTo(
                    overview,
                    { autoAlpha: 0, y: 22 * s, scale: 0.985 },
                    { autoAlpha: 1, y: 0, scale: 1, duration: 0.18, ease: "power3.out" },
                    at,
                  );
                } else {
                  tl.to(
                    overview,
                    { autoAlpha: 0, y: 22 * s, scale: 0.985, duration: 0.18, ease: "power3.in" },
                    at,
                  );
                }
                return;
              case "overview-plan": {
                // The planned order shows in the lane and its thumbnail with
                // Motion.snap. The windows move when Return applies the plan.
                const d = after.desktops[0];
                const b = before.desktops[0];
                const next = sortThumb(d.layout, d.order.length, 160, 100, d.ratio);
                for (const hue of d.order) {
                  const i = d.order.indexOf(hue);
                  const f = next[i];
                  tl.to(
                    q(`[data-thumb="${hue}"]`),
                    {
                      attr: { x: f.x, y: f.y, width: f.w, height: f.h },
                      fill: paneFill(hue, i, after.focused),
                      duration: 0.34,
                      ease: "back.out(1.4)",
                    },
                    at,
                  );
                  const dy = (i - b.order.indexOf(hue)) * 30 * s;
                  tl.to(
                    q(`[data-row="${hue}"]`),
                    { y: dy, duration: 0.34, ease: "back.out(1.4)" },
                    at,
                  );
                }
                return;
              }
              case "type":
                return;
            }
          }

          // Scroll drives which step plays. A step plays at real speed once its
          // caption arrives, and plays back when the caption leaves upward.
          STEPS.forEach((step, k) => {
            ScrollTrigger.create({
              trigger: q(`[data-cap="${step.id}"]`)[0],
              start: "top 35%",
              onEnter: () => {
                timelines.slice(0, k).forEach((x) => x.progress(1));
                timelines.slice(k + 1).forEach((x) => x.progress(0));
                if (reduce) timelines[k].progress(1);
                else timelines[k].play(0);
              },
              onLeaveBack: () => {
                timelines.slice(k + 1).forEach((x) => x.progress(0));
                if (reduce) timelines[k].progress(0);
                else timelines[k].reverse();
              },
            });
          });

          return () => {
            timelines.forEach((x) => x.kill());
          };
        },
      );
    },
    { scope: root },
  );

  return (
    <section ref={root} className="story" style={{ height: `${(STEPS.length + 1) * 100 + 30}vh` }}>
      <header className="nav" data-nav>
        <a href="/" className="lockup lockup--small" aria-label="CatWM">
          <Cat className="lockup__cat" />
          <span className="lockup__name">CatWM</span>
        </a>
        <a href="https://github.com/noxaur/ouch" className="pill pill--link">
          GitHub
        </a>
      </header>

      <div className="stage">
        <div className="screen" data-screen>
          <div className="desktops" data-desktops>
            {HUES.map((hue) => {
              const slot = startSlots.get(hue)!;
              return (
                <div
                  key={hue}
                  className="slab"
                  data-slab={hue}
                  style={slotStyle(slot.rect, slot.desktop, slot.z)}
                >
                  <div className="slab__face" style={{ background: WINDOWS[hue].color }} />
                </div>
              );
            })}
          </div>

          <svg className="modefx" data-modefx aria-hidden="true">
            <path data-stroke="head" className="modefx__head" pathLength={1} />
            <path data-stroke="head" className="modefx__head" pathLength={1} />
            <path data-stroke="line" className="modefx__line" pathLength={1} />
            <path data-stroke="line" className="modefx__line" pathLength={1} />
          </svg>

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

          <svg className="cursor" data-cursor viewBox="0 0 16 22" aria-hidden="true">
            <path
              d="M1 1l14 11.5-6.2.4 3.6 7-2.8 1.3-3.5-7.1L1 18z"
              fill="#000"
              stroke="#fff"
              strokeWidth="1.3"
              strokeLinejoin="round"
            />
          </svg>

          <div className="menu" data-menu aria-hidden="true">
            <div className="menu__title">Workspace templates</div>
            {[
              { icon: "plus" as const, title: "Save workspace…", key: "S" },
              { icon: "group" as const, title: TEMPLATE.name, key: "1" },
              { icon: "dim" as const, title: "Dim other windows", key: "D" },
              { icon: "blur" as const, title: "Blur other windows", key: "B" },
            ].map((row) => (
              <div key={row.title} className="menu__row" data-menu-row>
                <span className="menu__symbol">
                  <MenuIcon name={row.icon} />
                </span>
                <span className="menu__label">{row.title}</span>
                <kbd className="kbd-small">{row.key}</kbd>
              </div>
            ))}
          </div>

          <div className="overview" data-overview aria-hidden="true">
            <div className="overview__head">
              <span className="overview__title">Overview · 4 windows</span>
              <span className="segmented">
                <span className="segmented__item segmented__item--on">By task</span>
                <span className="segmented__item">By app</span>
                <span className="segmented__item">Focus</span>
                <span className="segmented__item">Start empty</span>
              </span>
            </div>
            <div className="overview__lanes">
              {OVERVIEW_STATE.desktops.map((d, i) => (
                <div key={i} className="lane" data-lane>
                  <div className="lane__head">
                    <span
                      className={`lane__number${d.order.length === 0 ? " lane__number--empty" : ""}`}
                    >
                      {i + 1}
                    </span>
                    <span
                      className={`lane__name${d.order.length === 0 ? " lane__name--placeholder" : ""}`}
                    >
                      Workspace {i + 1}
                    </span>
                    <span className="lane__count">
                      {d.order.length > 0
                        ? `${d.order.length} ${d.order.length === 1 ? "window" : "windows"}`
                        : ""}
                    </span>
                  </div>
                  <svg className="lane__thumb" viewBox="0 0 160 100" aria-hidden="true">
                    {d.order.map((hue, j) => {
                      const f = laneThumb[j];
                      return (
                        <rect
                          key={hue}
                          data-thumb={hue}
                          x={f.x}
                          y={f.y}
                          width={f.w}
                          height={f.h}
                          rx={3}
                          fill={paneFill(hue, j, OVERVIEW_STATE.focused)}
                        />
                      );
                    })}
                  </svg>
                  <span className="pill pill--layout">
                    <Glyph layout={d.layout} />
                    Tall
                  </span>
                  <div className="lane__rows">
                    {d.order.length === 0 && <div className="lane__empty" />}
                    {d.order.map((hue) => (
                      <div
                        key={hue}
                        className={`lane__row${hue === OVERVIEW_STATE.focused ? " lane__row--selected" : ""}`}
                        data-row={hue}
                      >
                        <span className="lane__icon" style={{ background: WINDOWS[hue].color }}>
                          {WINDOWS[hue].app[0]}
                        </span>
                        <span className="lane__title">{WINDOWS[hue].app}</span>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
              <div className="lane lane--add" data-lane>
                <div className="lane__head">
                  <span className="lane__number">+</span>
                  <span className="lane__name">Workspace 3</span>
                </div>
                <div className="lane__box" />
                <span className="pill pill--layout">
                  <Glyph layout="tall" />
                  Tall
                </span>
              </div>
              <div className="lane lane--close" data-lane>
                <div className="lane__head">
                  <span className="lane__number lane__number--danger">✕</span>
                  <span className="lane__name">Close</span>
                </div>
              </div>
            </div>
            <div className="overview__foot">
              <span className="obutton obutton--ghost">
                Revert <kbd>esc</kbd>
              </span>
              <span className="obutton obutton--primary">
                Done <kbd>↩</kbd>
              </span>
            </div>
          </div>
        </div>

        <div className="hero" data-hero>
          {hero}
        </div>
      </div>

      <div className="captions">
        <article className="cap cap--spacer" aria-hidden="true" />
        {STEPS.map((step) => (
          <article key={step.id} className="cap" data-cap={step.id}>
            <div className="cap__inner">
              <h2 className="cap__title">{step.title}</h2>
              {step.keys.length > 0 && (
                <div className="cap__keys">
                  {step.keys.map((key) => (
                    <span key={key.id} className="chord">
                      {key.caps.map((cap, i) => (
                        <kbd
                          key={i}
                          className="key"
                          data-key={i === key.caps.length - 1 ? `${step.id}:${key.id}` : undefined}
                        >
                          {cap}
                        </kbd>
                      ))}
                    </span>
                  ))}
                </div>
              )}
              <p className="cap__body">{step.body}</p>
              {step.id === "cli" && (
                <pre className="term">
                  <span className="term__prompt">$ </span>
                  <span data-term />
                  <span className="term__caret" />
                </pre>
              )}
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
