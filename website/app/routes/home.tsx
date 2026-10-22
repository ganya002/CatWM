import { useState } from "react";
import { useFetcher } from "react-router";

import { Cat } from "../catwm/Cat";
import { Story } from "../catwm/Story";
import { addSignup } from "../signup.server";
import type { Route } from "./+types/home";

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

export async function action({ request }: Route.ActionArgs) {
  const form = await request.formData();
  return addSignup(form.get("email"));
}

function InstallCommand() {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(INSTALL);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  };
  return (
    <div className="command">
      <code className="command__text">{INSTALL}</code>
      <button type="button" className="command__copy" onClick={copy} aria-live="polite">
        {copied ? "Copied" : "Copy"}
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
      <div className="hero__pill">
        <p className="hero__tagline">{TAGLINE}</p>
        <InstallCommand />
      </div>
    </>
  );
}

function Signup() {
  const fetcher = useFetcher<typeof action>();
  const busy = fetcher.state !== "idle";
  const done = fetcher.data?.ok === true;
  const error = fetcher.data?.ok === false ? fetcher.data.error : null;

  if (done) return <p className="foot__lead">Thanks. We will email you at release.</p>;
  return (
    <fetcher.Form method="post" className="signup">
      <div className="signup__field">
        <input
          type="email"
          name="email"
          required
          autoComplete="email"
          placeholder="you@example.com"
          aria-label="Email"
          className="signup__input"
        />
        <button type="submit" disabled={busy} className="signup__submit">
          {busy ? "Sending…" : "Email me at release"}
        </button>
      </div>
      {error && <p className="signup__error">{error}</p>}
    </fetcher.Form>
  );
}

export default function Home() {
  return (
    <>
      <Story hero={<Hero />} />
      <footer className="foot">
        <h2 className="foot__title">Install the beta</h2>
        <InstallCommand />
        <p className="foot__lead">
          The public release is coming. Leave your email and we will tell you once.
        </p>
        <Signup />
        <div className="foot__links">
          <a href="https://github.com/noxaur/ouch" className="pill pill--link">
            GitHub
          </a>
          <a
            href="https://github.com/noxaur/ouch/blob/main/CONTRIBUTING.md"
            className="pill pill--link"
          >
            Contributing
          </a>
        </div>
      </footer>
    </>
  );
}
