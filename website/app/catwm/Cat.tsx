import gsap from "gsap";
import { useEffect, useId, useRef } from "react";

// The CatWM cat. The eye geometry and the feelings are the ones in
// docs/design/cat-feelings.html, so the web cat behaves like the app cat.

export const CAT_PATH =
  "M 231 42 C 234 31 245 29 250 36 C 268 60 294 90 310 104 C 330 116 356 108 384 92 C 408 78 430 60 444 40 C 449 33 458 38 455 50 C 448 84 438 112 430 136 C 408 206 368 300 356 340 C 348 368 398 408 399 452 C 400 484 372 506 330 506 C 250 508 150 508 96 496 C 60 488 40 450 52 400 C 70 326 167 264 178 226 C 194 165 212 103 231 42 Z";

type Eye = { x: number; y: number; tilt: number; chord: number; rise: number; width: number };
type Field = keyof Eye;
const FIELDS: Field[] = ["x", "y", "tilt", "chord", "rise", "width"];

type PoseSpec = Partial<Record<Field, number | [number, number]>> & {
  spring?: keyof typeof SPRINGS;
  lag?: number;
  blinkSpeed?: number;
};

const BASE: Record<Field, [number, number] | number> = {
  x: [256, 348],
  y: [173, 191],
  tilt: [-11, 19],
  chord: [42, 40],
  rise: 9,
  width: 13,
};

const POSES: Record<string, PoseSpec> = {
  content: {},
  alert: { x: [258, 352], y: [168, 186], tilt: 0, chord: 0, rise: 0, width: 24, spring: "snappy" },
  sad: { y: [178, 196], tilt: [-24, 28], chord: [40, 38], rise: -8, lag: 60 },
  annoyed: { x: [256, 350], y: [176, 190], tilt: [24, -6], chord: 40, rise: 0 },
  sleepy: {
    y: [184, 198],
    tilt: [-4, 10],
    chord: [40, 38],
    rise: 4,
    spring: "lazy",
    blinkSpeed: 2.5,
  },
  shut: { y: [186, 199], tilt: [-4, 10], chord: [38, 36], rise: 0, spring: "lazy", blinkSpeed: 0 },
};

const SPRINGS = {
  smooth: { stiffness: 170, damping: 26 },
  snappy: { stiffness: 420, damping: 26 },
  lazy: { stiffness: 45, damping: 13.4 },
};

const SCRIPT: [string, number][] = [
  ["content", 2600],
  ["alert", 1600],
  ["content", 1400],
  ["sad", 2200],
  ["content", 1400],
  ["annoyed", 2000],
  ["content", 1400],
  ["sleepy", 2000],
  ["shut", 1400],
  ["sleepy", 600],
  ["blink", 500],
  ["content", 0],
];

const BLINK = { close: 70, hold: 40, open: 140 };
const SUBSTEP = 1 / 240;

type Pose = {
  lag: number;
  blinkSpeed: number;
  spring: { stiffness: number; damping: number };
  l: Eye;
  r: Eye;
};

function resolvePose(name: string): Pose {
  const spec = { spring: "smooth" as const, lag: 24, blinkSpeed: 1, ...POSES[name] };
  const eye = (side: 0 | 1): Eye => {
    const o = {} as Eye;
    for (const f of FIELDS) {
      const v = f in spec ? spec[f]! : BASE[f];
      o[f] = Array.isArray(v) ? v[side] : v;
    }
    return o;
  };
  return {
    lag: spec.lag,
    blinkSpeed: spec.blinkSpeed,
    spring: SPRINGS[spec.spring],
    l: eye(0),
    r: eye(1),
  };
}

const blinkLength = (s: number) => (BLINK.close + BLINK.hold + BLINK.open) * s;

function lidAt(t: number, s: number) {
  const smooth = (x: number) => x * x * (3 - 2 * x);
  const c = BLINK.close * s;
  const h = c + BLINK.hold * s;
  const o = h + BLINK.open * s;
  if (t < 0 || t >= o) return 0;
  if (t < c) return smooth(t / c);
  if (t < h) return 1;
  return 1 - smooth((t - h) / (o - h));
}

function withLid(e: Eye, lid: number): Eye {
  if (!lid) return e;
  const shut: Eye = {
    x: e.x,
    y: e.y + 2,
    tilt: e.tilt,
    chord: Math.max(e.chord, 24) * 0.92,
    rise: e.rise * -0.15,
    width: Math.min(e.width, 12),
  };
  const o = {} as Eye;
  for (const f of FIELDS) o[f] = e[f] + (shut[f] - e[f]) * lid;
  return o;
}

function arcD(e: Eye) {
  const a = (e.tilt * Math.PI) / 180;
  const ux = Math.cos(a);
  const uy = Math.sin(a);
  const nx = uy;
  const ny = -ux;
  const h = Math.max(0, e.chord) / 2;
  const p = (t: number, r: number) =>
    `${(e.x + ux * t + nx * r).toFixed(2)} ${(e.y + uy * t + ny * r).toFixed(2)}`;
  return `M ${p(-h, 0)} C ${p(-h * 0.55, e.rise * 1.33)} ${p(h * 0.55, e.rise * 1.33)} ${p(h, 0)}`;
}

function eyeMatrix(e: Eye, lookX: number, lookY: number) {
  const R = 118;
  const clamp = (v: number) => Math.max(-1, Math.min(1, v));
  const restX = Math.asin(clamp((e.x - 302) / R));
  const restY = Math.asin(clamp((e.y - 184) / R));
  const ax = restX + lookX;
  const ay = restY + lookY;
  const sx = Math.max(0, Math.cos(ax) / Math.cos(restX));
  const sy = Math.max(0, Math.cos(ay) / Math.cos(restY));
  const tx = 302 + R * Math.sin(ax) - sx * e.x;
  const ty = 184 + R * Math.sin(ay) - sy * e.y;
  return `matrix(${sx.toFixed(4)} 0 0 ${sy.toFixed(4)} ${tx.toFixed(2)} ${ty.toFixed(2)})`;
}

function idleMotion(t: number) {
  const w = (period: number) => Math.sin((2 * Math.PI * t) / period);
  return {
    stretch: 1 + 0.012 * (1 - Math.cos((2 * Math.PI * t) / 3.4)),
    lean: 1.2 * w(9),
    lookX: 0.22 * w(7.3) + 0.08 * w(3.1),
    lookY: 0.12 * w(5.7),
  };
}

const REST = resolvePose("content");

// The moves, ported from Sources/ouch/UI/Theme/CatMotion.swift. Each move is
// keyframe tracks over seconds. lift is a share of the body height, stretch
// squashes about the feet, lean is degrees, and lookX / lookY turn the face on
// the head sphere, so a lookX of 2π is a full spin.
type Motion = { lift: number; stretch: number; lean: number; lookX: number; lookY: number };
type Curve = "ease" | "easeIn" | "easeOut" | "linear";
type Track = { times: number[]; values: number[]; curves?: Curve[] };
type CatMove = "hop" | "spin" | "wiggle" | "look";

const EASE: Record<Curve, (p: number) => number> = {
  ease: (p) => p * p * (3 - 2 * p),
  easeIn: (p) => p * p,
  easeOut: (p) => 1 - (1 - p) * (1 - p),
  linear: (p) => p,
};

const MOVES: Record<CatMove, Partial<Record<keyof Motion, Track>>> = {
  hop: {
    lift: {
      times: [0, 0.14, 0.35, 0.56, 0.66, 0.74],
      values: [0, 0, 0.22, 0, 0.03, 0],
      curves: ["linear", "easeOut", "easeIn", "easeOut", "easeIn"],
    },
    stretch: {
      times: [0, 0.14, 0.22, 0.35, 0.56, 0.62, 0.74, 0.8, 0.92, 1.05],
      values: [1, 0.8, 1.16, 1, 1.06, 0.8, 0.94, 1.06, 0.98, 1],
    },
    lookY: { times: [0, 0.14, 0.35, 0.6, 0.9], values: [0, 0.2, -0.35, -0.1, 0] },
  },
  spin: {
    lift: {
      times: [0, 0.14, 0.4, 0.7, 0.78, 0.86],
      values: [0, 0, 0.14, 0, 0.02, 0],
      curves: ["linear", "easeOut", "easeIn", "easeOut", "easeIn"],
    },
    stretch: {
      times: [0, 0.14, 0.24, 0.4, 0.7, 0.76, 0.88, 1.0],
      values: [1, 0.86, 1.08, 1, 1.03, 0.88, 1.03, 1],
    },
    lookX: { times: [0, 0.12, 0.75, 0.9], values: [0, -0.25, 2 * Math.PI + 0.12, 2 * Math.PI] },
  },
  wiggle: {
    stretch: { times: [0, 0.1, 0.3, 0.5, 0.8], values: [1, 0.92, 1.05, 0.98, 1] },
    lean: { times: [0, 0.1, 0.26, 0.42, 0.56, 0.68, 0.8], values: [0, 10, -10, 7, -4, 1.5, 0] },
    lookX: { times: [0, 0.1, 0.26, 0.42, 0.56, 0.8], values: [0, -0.35, 0.35, -0.25, 0.12, 0] },
  },
  look: {
    stretch: { times: [0, 0.2, 0.35, 1.1, 1.25, 1.9], values: [1, 1.03, 1, 1, 1.03, 1] },
    lookX: { times: [0, 0.3, 1.0, 1.35, 1.95, 2.3], values: [0, 0.75, 0.75, -0.7, -0.7, 0] },
    lookY: { times: [0, 0.3, 1.0, 1.35, 1.95, 2.3], values: [0, -0.5, -0.5, 0.15, 0.15, 0] },
  },
};

function trackValue({ times, values, curves = [] }: Track, time: number) {
  if (time <= times[0]) return values[0];
  const next = times.findIndex((t) => t > time);
  if (next < 0) return values[values.length - 1];
  const start = next - 1;
  const p = (time - times[start]) / (times[next] - times[start]);
  return values[start] + (values[next] - values[start]) * EASE[curves[start] ?? "ease"](p);
}

const moveDuration = (move: CatMove) =>
  Math.max(...Object.values(MOVES[move]).map((t) => t.times[t.times.length - 1]));

// The body is 475 of the 512 viewBox units tall; lift is a share of it.
const BODY_HEIGHT = 475 / 512;

// An eye turned past the edge of the head sphere is out of view behind it.
function eyeShown(e: Eye, lookX: number, lookY: number) {
  const clamp = (v: number) => Math.max(-1, Math.min(1, v));
  const ax = Math.asin(clamp((e.x - 302) / 118)) + lookX;
  const ay = Math.asin(clamp((e.y - 184) / 118)) + lookY;
  return Math.cos(ax) > 0 && Math.cos(ay) > 0;
}

type Props = {
  className?: string;
  // Play the feelings script (content, alert, sad, annoyed, sleepy). Off: content with idle blinks.
  feelings?: boolean;
  label?: string;
};

export function Cat({ className, feelings = false, label = "The CatWM cat" }: Props) {
  const id = useId();
  const wrap = useRef<HTMLSpanElement>(null);
  const svg = useRef<SVGSVGElement>(null);
  const left = useRef<SVGPathElement>(null);
  const right = useRef<SVGPathElement>(null);

  useEffect(() => {
    const el = svg.current;
    const l = left.current;
    const r = right.current;
    if (!el || !l || !r) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let pose = resolvePose("content");
    type Spring = { value: number; target: number; velocity: number };
    const eyes: Record<"l" | "r", Record<Field, Spring>> = { l: {} as never, r: {} as never };
    for (const k of ["l", "r"] as const) {
      for (const f of FIELDS) eyes[k][f] = { value: pose[k][f], target: pose[k][f], velocity: 0 };
    }
    const born = performance.now();
    let last = born;
    let clock = 0;
    let pending: { at: number; side: "l" | "r"; values: Eye }[] = [];
    let blinks: { at: number; s: number }[] = [];
    let move: { name: CatMove; start: number } | null = null;
    let idleT = 0;
    let scriptT = 0;
    let raf = 0;
    let i = 0;
    let running = true;

    const read = (k: "l" | "r"): Eye => {
      const o = {} as Eye;
      for (const f of FIELDS) o[f] = eyes[k][f].value;
      return o;
    };

    // Idle motion plus the playing move, combined the way CatPuppet does.
    const motionAt = (now: number): Motion => {
      const m: Motion = { lift: 0, ...idleMotion((now - born) / 1000) };
      if (!move) return m;
      const at = (now - move.start) / 1000;
      if (at >= moveDuration(move.name)) {
        move = null;
        return m;
      }
      const tracks = MOVES[move.name];
      const value = (k: keyof Motion, rest: number) =>
        tracks[k] ? trackValue(tracks[k], at) : rest;
      m.lift = value("lift", 0);
      m.stretch *= value("stretch", 1);
      m.lean += value("lean", 0);
      m.lookX += value("lookX", 0);
      m.lookY += value("lookY", 0);
      return m;
    };

    const draw = (a: Eye, b: Eye, lid: number, m: Motion) => {
      for (const [path, eye] of [
        [l, withLid(a, lid)],
        [r, withLid(b, lid)],
      ] as const) {
        path.setAttribute("d", arcD(eye));
        path.setAttribute("transform", eyeMatrix(eye, m.lookX, m.lookY));
        path.setAttribute("stroke-width", Math.max(0.5, eye.width).toFixed(2));
        path.setAttribute("stroke-opacity", eyeShown(eye, m.lookX, m.lookY) ? "1" : "0");
      }
      const width = 1 + (1 - m.stretch) * 0.7;
      el.style.transform = `translateY(${(-m.lift * BODY_HEIGHT * 100).toFixed(3)}%) rotate(${m.lean.toFixed(3)}deg) scale(${width.toFixed(4)}, ${m.stretch.toFixed(4)})`;
    };

    const frame = (now: number) => {
      if (!running) return;
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      clock += dt * 1000;
      pending = pending.filter((p) => {
        if (clock < p.at) return true;
        for (const f of FIELDS) eyes[p.side][f].target = p.values[f];
        return false;
      });
      blinks = blinks.filter((b) => clock - b.at < blinkLength(b.s));
      const n = Math.max(1, Math.ceil(dt / SUBSTEP));
      const h = dt / n;
      for (const k of ["l", "r"] as const) {
        for (const f of FIELDS) {
          const s = eyes[k][f];
          if (s.value === s.target && s.velocity === 0) continue;
          for (let j = 0; j < n; j++) {
            const acc =
              -pose.spring.stiffness * (s.value - s.target) - pose.spring.damping * s.velocity;
            s.velocity += acc * h;
            s.value += s.velocity * h;
            if (Math.abs(s.velocity) < 0.005 && Math.abs(s.value - s.target) < 0.005) {
              s.value = s.target;
              s.velocity = 0;
              break;
            }
          }
        }
      }
      const lid = blinks.reduce((m, b) => Math.max(m, lidAt(clock - b.at, b.s)), 0);
      draw(read("l"), read("r"), lid, motionAt(now));
      raf = requestAnimationFrame(frame);
    };

    const scheduleIdle = () => {
      clearTimeout(idleT);
      idleT = window.setTimeout(
        () => {
          if (pose.blinkSpeed) blink(Math.random() < 0.18);
          else scheduleIdle();
        },
        2400 + Math.random() * 3800,
      );
    };

    const blink = (dbl: boolean) => {
      scheduleIdle();
      const s = pose.blinkSpeed || 1;
      blinks.push({ at: clock, s });
      if (dbl) blinks.push({ at: clock + blinkLength(s) + 70, s });
    };

    const to = (name: string) => {
      pose = resolvePose(name);
      pending = pending.filter((p) => p.side !== "r");
      for (const f of FIELDS) eyes.l[f].target = pose.l[f];
      pending.push({ at: clock + pose.lag, side: "r", values: pose.r });
    };

    const next = () => {
      const step = SCRIPT[i];
      i = (i + 1) % SCRIPT.length;
      if (step[0] === "blink") blink(false);
      else to(step[0]);
      scriptT = window.setTimeout(next, step[1]);
    };

    // The pointer: a hop and an alert look on hover, and a click plays the
    // app's spin. A new move restarts from its start, as in the app.
    const box = wrap.current;
    const onEnter = () => {
      to("alert");
      gsap.to(box, { yPercent: -6, duration: 0.3, ease: "back.out(2.5)", overwrite: "auto" });
    };
    const onLeave = () => {
      to("content");
      gsap.to(box, { yPercent: 0, duration: 0.4, ease: "power2.out", overwrite: "auto" });
    };
    const onClick = () => {
      move = { name: "spin", start: performance.now() };
    };
    if (box) {
      box.addEventListener("pointerenter", onEnter);
      box.addEventListener("pointerleave", onLeave);
      box.addEventListener("click", onClick);
    }

    scheduleIdle();
    if (feelings) next();
    raf = requestAnimationFrame(frame);
    return () => {
      running = false;
      cancelAnimationFrame(raf);
      clearTimeout(idleT);
      clearTimeout(scriptT);
      if (box) {
        box.removeEventListener("pointerenter", onEnter);
        box.removeEventListener("pointerleave", onLeave);
        box.removeEventListener("click", onClick);
        gsap.killTweensOf(box);
      }
    };
  }, [feelings]);

  const maskId = `cat-eyes-${id.replace(/:/g, "")}`;
  return (
    <span ref={wrap} className={`cat ${className ?? ""}`}>
      <svg
        ref={svg}
        viewBox="0 0 512 512"
        role="img"
        aria-label={label}
        className="cat__face"
        style={{ transformOrigin: "49.2% 99%" }}
      >
        <defs>
          <mask id={maskId}>
            <rect width="512" height="512" fill="#fff" />
            <g fill="none" stroke="#000" strokeLinecap="round">
              <path
                ref={left}
                d={arcD(REST.l)}
                strokeWidth={REST.l.width}
                transform={eyeMatrix(REST.l, 0, 0)}
              />
              <path
                ref={right}
                d={arcD(REST.r)}
                strokeWidth={REST.r.width}
                transform={eyeMatrix(REST.r, 0, 0)}
              />
            </g>
          </mask>
        </defs>
        <path d={CAT_PATH} fill="currentColor" mask={`url(#${maskId})`} />
      </svg>
    </span>
  );
}
