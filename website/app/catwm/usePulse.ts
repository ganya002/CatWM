import gsap from "gsap";
import { type RefObject, useEffect } from "react";

// The pulse: a circle grows out of the install button until it covers its
// section, then shrinks back into it. The button sits above the veil, so it is the one
// thing the pulse leaves alone.
export function usePulse(root: RefObject<HTMLElement | null>, color: string) {
  useEffect(() => {
    const el = root.current;
    const veil = el?.querySelector<HTMLElement>("[data-pulse]");
    const cta = el?.querySelector<HTMLElement>("[data-cta]");
    if (!el || !veil || !cta) return;

    let running: gsap.core.Timeline | null = null;
    const pulse = () => {
      const area = el.getBoundingClientRect();
      const b = cta.getBoundingClientRect();
      const x = b.left + b.width / 2 - area.left;
      const y = b.top + b.height / 2 - area.top;
      const reach = Math.hypot(Math.max(x, area.width - x), Math.max(y, area.height - y));
      veil.style.background = color;
      running?.kill();
      cta.classList.add("is-lit");
      const from = `circle(${b.width * 0.5}px at ${x}px ${y}px)`;
      running = gsap
        .timeline({ onComplete: () => cta.classList.remove("is-lit") })
        .fromTo(
          veil,
          { clipPath: from, opacity: 1 },
          { clipPath: `circle(${reach}px at ${x}px ${y}px)`, duration: 0.65, ease: "power2.out" },
          0,
        )
        .to(veil, { clipPath: from, duration: 0.65, ease: "power2.in" }, 0.85)
        .set(veil, { opacity: 0 })
        .fromTo(cta, { "--spin": "0deg" }, { "--spin": "180deg", duration: 1.5, ease: "none" }, 0);
    };
    cta.addEventListener("click", pulse);
    return () => {
      cta.removeEventListener("click", pulse);
      running?.kill();
    };
  }, [root, color]);
}
