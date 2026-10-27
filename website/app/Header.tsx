import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useRef } from "react";
import { Link, NavLink } from "react-router";

import { Cat } from "~/catwm/Cat";

// The site header: the small lockup and the pages as pills, on flat black.
// With `reveal` it stays out of the hero and slides in when the first card covers it.
export function Header({ reveal = false }: { reveal?: boolean }) {
  const root = useRef<HTMLElement>(null);

  useGSAP(
    () => {
      const el = root.current;
      const card = document.querySelector<HTMLElement>(".deck .card");
      if (!reveal || !el || !card) return;
      gsap.registerPlugin(ScrollTrigger);
      ScrollTrigger.create({
        trigger: card,
        start: "top top",
        onEnter: () => el.setAttribute("data-shown", ""),
        onLeaveBack: () => el.removeAttribute("data-shown"),
      });
      return () => el.removeAttribute("data-shown");
    },
    { dependencies: [reveal] },
  );

  return (
    <header ref={root} className={`site ${reveal ? "site--reveal" : ""}`}>
      <Link to="/" className="lockup lockup--small" aria-label="CatWM home">
        <Cat className="lockup__cat" />
        <span className="lockup__name">CatWM</span>
      </Link>
      <nav aria-label="Site">
        <ul className="site__nav">
          <li>
            <NavLink to="/features" className="site__link">
              Features
            </NavLink>
          </li>
          <li>
            <Link to="/features#agents" className="site__link">
              For agents
            </Link>
          </li>
          <li>
            <NavLink to="/roadmap" className="site__link">
              Roadmap
            </NavLink>
          </li>
        </ul>
      </nav>
    </header>
  );
}
