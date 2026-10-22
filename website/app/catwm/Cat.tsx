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

type Props = {
  className?: string;
  // Play the feelings script (content, alert, sad, annoyed, sleepy). Off: content with idle blinks.
  feelings?: boolean;
  label?: string;
};

export function Cat({ className, feelings = false, label = "The CatWM cat" }: Props) {
  const id = useId();
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

    const draw = (a: Eye, b: Eye, lid: number, m: ReturnType<typeof idleMotion>) => {
      const ea = withLid(a, lid);
      const eb = withLid(b, lid);
      l.setAttribute("d", arcD(ea));
      r.setAttribute("d", arcD(eb));
      l.setAttribute("transform", eyeMatrix(ea, m.lookX, m.lookY));
      r.setAttribute("transform", eyeMatrix(eb, m.lookX, m.lookY));
      l.setAttribute("stroke-width", Math.max(0.5, ea.width).toFixed(2));
      r.setAttribute("stroke-width", Math.max(0.5, eb.width).toFixed(2));
      const width = 1 + (1 - m.stretch) * 0.7;
      el.style.transform = `rotate(${m.lean.toFixed(3)}deg) scale(${width.toFixed(4)}, ${m.stretch.toFixed(4)})`;
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
      draw(read("l"), read("r"), lid, idleMotion((now - born) / 1000));
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

    scheduleIdle();
    if (feelings) next();
    raf = requestAnimationFrame(frame);
    return () => {
      running = false;
      cancelAnimationFrame(raf);
      clearTimeout(idleT);
      clearTimeout(scriptT);
    };
  }, [feelings]);

  const rest = { stretch: 1, lean: 0, lookX: 0, lookY: 0 };
  const maskId = `cat-eyes-${id.replace(/:/g, "")}`;
  return (
    <svg
      ref={svg}
      viewBox="0 0 512 512"
      role="img"
      aria-label={label}
      className={className}
      style={{ transformOrigin: "50% 99.2%" }}
    >
      <defs>
        <mask id={maskId}>
          <rect width="512" height="512" fill="#fff" />
          <g fill="none" stroke="#000" strokeLinecap="round">
            <path
              ref={left}
              d={arcD(REST.l)}
              strokeWidth={REST.l.width}
              transform={eyeMatrix(REST.l, rest.lookX, rest.lookY)}
            />
            <path
              ref={right}
              d={arcD(REST.r)}
              strokeWidth={REST.r.width}
              transform={eyeMatrix(REST.r, rest.lookX, rest.lookY)}
            />
          </g>
        </mask>
      </defs>
      <path d={CAT_PATH} fill="currentColor" mask={`url(#${maskId})`} />
    </svg>
  );
}
