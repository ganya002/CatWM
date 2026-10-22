import { useState } from "react";

import { Cards } from "../catwm/Cards";
import { Cat } from "../catwm/Cat";
import { Stage } from "../catwm/Stage";

const SITE = "https://catwm.perwko.com";
const INSTALL = "curl -fsSL https://catwm.perwko.com/install.sh | sh -s -- --beta";
const TAGLINE = "A simple, modern, and fast tiling window manager for macOS.";

export function meta() {
  return [
    { title: "CatWM" },
    { name: "description", content: TAGLINE },
    { name: "theme-color", content: "#000000" },

    { property: "og:type", content: "website" },
    { property: "og:site_name", content: "CatWM" },
    { property: "og:title", content: "CatWM" },
    { property: "og:description", content: TAGLINE },
    { property: "og:url", content: SITE },
    { property: "og:image", content: `${SITE}/og.png` },
    { property: "og:image:type", content: "image/png" },
    { property: "og:image:width", content: "1200" },
    { property: "og:image:height", content: "630" },
    { property: "og:image:alt", content: "The CatWM app icon next to tiled windows on macOS." },

    { name: "twitter:card", content: "summary_large_image" },
    { name: "twitter:title", content: "CatWM" },
    { name: "twitter:description", content: TAGLINE },
    { name: "twitter:image", content: `${SITE}/og.png` },
  ];
}

// One button. It copies the install command, then says what to do with it.
function Install({ cta = false }: { cta?: boolean }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(INSTALL);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  };
  return (
    <div className="install">
      <button
        type="button"
        className="install__button"
        data-cta={cta || undefined}
        onClick={copy}
        aria-live="polite"
      >
        <span className="install__labels">
          <span className="install__label" data-shown={!copied || undefined}>
            Install the beta
          </span>
          <span className="install__label" data-shown={copied || undefined}>
            Paste in Terminal
          </span>
        </span>
      </button>
    </div>
  );
}

function Hero() {
  return (
    <>
      <h1 className="lockup">
        <Cat className="lockup__cat" feelings />
        <span className="lockup__name">CatWM</span>
      </h1>
      <Install cta />
    </>
  );
}

function Last() {
  return (
    <>
      <h2 className="card__title">Public release soon.</h2>
      <Install />
      <a href="https://github.com/noxaur/ouch" className="pill pill--link">
        GitHub
      </a>
    </>
  );
}

export default function Home() {
  return (
    <div className="deck">
      <Stage hero={<Hero />} />
      <Cards last={<Last />} />
    </div>
  );
}
