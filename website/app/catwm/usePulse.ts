import gsap from "gsap";
import { type RefObject, useEffect } from "react";

// The pulse: a circle grows out of the install button until it covers its
// section, then shrinks back into it. The button sits above the veil, so it is the one
// thing the pulse leaves alone.
export function usePulse(root: RefObject<HTMLElement | null>, color: string, ink: string) {
  useEffect(() => {
    const el = root.current;
    const veil = el?.querySelector<HTMLElement>("[data-pulse]");
    const text = el?.querySelector<HTMLElement>(".pulse__text");
    const anchor = el?.querySelector<HTMLElement>(".lockup__name, .card__title");
    const cta = el?.querySelector<HTMLElement>("[data-cta]");
    if (!el || !veil || !text || !cta) return;

    let running: gsap.core.Timeline | null = null;
    const pulse = () => {
      const area = el.getBoundingClientRect();
      const b = cta.getBoundingClientRect();
      const x = b.left + b.width / 2 - area.left;
      const y = b.top + b.height / 2 - area.top;
      const reach = Math.hypot(Math.max(x, area.width - x), Math.max(y, area.height - y));
      if (anchor) {
        // The message takes the spot of the CatWM name (or the closing title).
        const a = anchor.getBoundingClientRect();
        // Stay clear of the button, which sits above the veil: keep the descenders out from behind it.
        const room = b.top - area.top - text.offsetHeight * 1.2;
        text.style.top = `${Math.min(a.top + a.height / 2 - area.top, room)}px`;
      }
      veil.style.background = color;
      veil.style.color = ink;
      running?.kill();
      cta.classList.add("is-lit");
      const from = `circle(0px at ${x}px ${y}px)`;
      running = gsap
        .timeline({ onComplete: () => cta.classList.remove("is-lit") })
        .fromTo(
          veil,
          { clipPath: from, opacity: 1 },
          { clipPath: `circle(${reach}px at ${x}px ${y}px)`, duration: 0.9, ease: "expo.inOut" },
          0,
        )
        .to(veil, { clipPath: from, duration: 0.9, ease: "expo.in" }, 2.5)
        .set(veil, { opacity: 0 })
        .fromTo(cta, { "--spin": "0deg" }, { "--spin": "180deg", duration: 3.4, ease: "none" }, 0);
    };
    cta.addEventListener("click", pulse);
    return () => {
      cta.removeEventListener("click", pulse);
      running?.kill();
    };
  }, [root, color, ink]);
}
