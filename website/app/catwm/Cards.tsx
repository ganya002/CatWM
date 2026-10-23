import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { type CSSProperties, type ReactNode, useEffect, useRef } from "react";

import { CARDS, MORE } from "./cards";
import { Demo } from "./Demo";
import { WINDOWS } from "./script";
import { usePulse } from "./usePulse";

// A notch on the top edge of the first card, with an arrow. It peeks above the hero
// and rides up with the card. The card colour fills it from the bottom up as the page
// scrolls, so it fills as fast as the visitor scrolls.
function ScrollHint() {
  const root = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    const update = () =>
      el.style.setProperty("--fill", String(Math.min(1, window.scrollY / el.offsetHeight)));
    update();
    window.addEventListener("scroll", update, { passive: true });
    return () => window.removeEventListener("scroll", update);
  }, []);

  const layer = (
    <>
      <svg className="scroll-hint__notch" viewBox="0 0 220 72" aria-hidden="true">
        <path d="M0 72C20 72 35 67 42 48A72 72 0 0 1 178 48C185 67 200 72 220 72Z" />
      </svg>
      <svg className="scroll-hint__arrow" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M12 4v15M5 12l7 7 7-7" />
      </svg>
    </>
  );

  return (
    <button
      ref={root}
      type="button"
      className="scroll-hint"
      aria-label="Scroll down"
      onClick={(e) => {
        const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        e.currentTarget.closest(".card")?.scrollIntoView({ behavior: still ? "auto" : "smooth" });
      }}
    >
      {layer}
      <span className="scroll-hint__fill">{layer}</span>
    </button>
  );
}

// The feature cards. Each one sticks at the top, and as the next one rises
// the page behind it recedes: it scales down and dims while the new page
// slides over it.
export function Cards({ last }: { last: ReactNode }) {
  const root = useRef<HTMLDivElement>(null);
  const lastCard = useRef<HTMLElement>(null);
  usePulse(lastCard, "#fff");

  useGSAP(
    () => {
      gsap.registerPlugin(ScrollTrigger);
      const deck = root.current?.closest(".deck");
      if (!deck) return;
      const pages = [
        deck.querySelector<HTMLElement>(".stage"),
        ...deck.querySelectorAll<HTMLElement>(".card"),
      ].filter((p): p is HTMLElement => p !== null);

      const mm = gsap.matchMedia();
      mm.add({ reduce: "(prefers-reduced-motion: reduce)" }, (ctx) => {
        const { reduce } = ctx.conditions as { reduce: boolean };
        if (reduce) return;
        pages.forEach((page, i) => {
          const next = pages[i + 1];
          if (!next) return;
          gsap.fromTo(
            page,
            { scale: 1, filter: "brightness(1)" },
            {
              scale: 0.92,
              filter: "brightness(0.45)",
              ease: "none",
              scrollTrigger: { trigger: next, start: "top bottom", end: "top top", scrub: true },
            },
          );
        });
      });
    },
    { scope: root },
  );

  return (
    <div ref={root}>
      {CARDS.map((card, i) => (
        <section
          key={card.id}
          className="card"
          style={{ "--card": card.color, "--i": i + 1 } as CSSProperties}
        >
          {i === 0 && <ScrollHint />}
          <div className="card__inner">
            <div className="card__copy">
              <h2 className="card__title">{card.title}</h2>
              <p className="card__line">{card.line}</p>
            </div>
            <Demo card={card} />
          </div>
        </section>
      ))}
      <section className="card card--more" style={{ "--i": CARDS.length + 1 } as CSSProperties}>
        <div className="card__inner">
          <div className="card__copy">
            <h2 className="card__title">And much more.</h2>
            <a className="more__link" href="/features">
              See all features
            </a>
          </div>
          <ul className="more">
            {MORE.map((item) => (
              <li
                key={item.name}
                className="more__item"
                style={{ "--dot": WINDOWS[item.hue].color } as CSSProperties}
              >
                {item.name}
              </li>
            ))}
          </ul>
        </div>
      </section>
      <section
        ref={lastCard}
        className="card card--last"
        style={{ "--i": CARDS.length + 2 } as CSSProperties}
      >
        <div className="pulse" data-pulse aria-hidden="true" />
        <div className="card__inner card__inner--center">{last}</div>
      </section>
    </div>
  );
}
