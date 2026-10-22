import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { type CSSProperties, type ReactNode, useRef } from "react";

import { CARDS } from "./cards";
import { Demo } from "./Demo";

// The feature cards. Each one sticks at the top, and as the next one rises
// the page behind it recedes: it scales down and dims while the new page
// slides over it.
export function Cards({ last }: { last: ReactNode }) {
  const root = useRef<HTMLDivElement>(null);

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
          <div className="card__inner">
            <div className="card__copy">
              <h2 className="card__title">{card.title}</h2>
              <p className="card__line">{card.line}</p>
            </div>
            <Demo card={card} />
          </div>
        </section>
      ))}
      <section className="card card--last" style={{ "--i": CARDS.length + 1 } as CSSProperties}>
        <div className="card__inner card__inner--center">{last}</div>
      </section>
    </div>
  );
}
