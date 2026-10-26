import { type CSSProperties, useEffect, useState } from "react";

import { Demo } from "~/catwm/Demo";
import { WINDOWS } from "~/catwm/script";

import {
  AGENT,
  type Category,
  type Control,
  type Feature,
  type Media,
  type Settings,
  USER,
} from "./catalog";

// One cap for each chord, with the glyphs together, like a macOS menu.
function Keys({ keys }: { keys: string[][] }) {
  return (
    <span className="keys">
      {keys.map((chord) => (
        <kbd key={chord.join("")} className="cap">
          {chord.join(chord.some((c) => c.length > 1) ? " " : "")}
        </kbd>
      ))}
    </span>
  );
}

// The commands and the config lines, as one small terminal.
function Usage({ cli = [], config = [] }: { cli?: string[]; config?: string[] }) {
  if (cli.length === 0 && config.length === 0) return null;
  return (
    <pre className="usage">
      <code>
        {cli.map((c) => (
          <span key={c} className="usage__line">
            <span className="usage__dim">$ </span>
            {c}
          </span>
        ))}
        {config.length > 0 && (
          <span className="usage__line usage__dim" data-gap={cli.length > 0 || undefined}>
            # catwm.conf
          </span>
        )}
        {config.map((c) => (
          <span key={c} className="usage__line">
            {c}
          </span>
        ))}
      </code>
    </pre>
  );
}

// The control a Settings row shows by default, drawn like the app draws it.
function ControlView({ control }: { control: Control }) {
  if (typeof control === "boolean")
    return (
      <span
        className="switch"
        data-on={control || undefined}
        role="img"
        aria-label={control ? "On" : "Off"}
      />
    );
  if (typeof control === "string")
    return (
      <span className="menu">
        {control}
        <svg className="menu__chevrons" viewBox="0 0 8 12" aria-hidden="true">
          <path d="M1.5 4.5 4 2l2.5 2.5M1.5 7.5 4 10l2.5-2.5" />
        </svg>
      </span>
    );
  return <span className="pill">{control.button}</span>;
}

// Where a user finds the feature: the Settings pane, its rows and their defaults.
function SettingsPane({ settings }: { settings: Settings }) {
  return (
    <figure className="frame">
      <figcaption className="frame__caption">Settings › {settings.pane}</figcaption>
      <ul className="frame__body pane">
        {settings.rows.map(([label, control]) => (
          <li key={label} className="pane__row">
            <span className="pane__label">{label}</span>
            {control !== undefined && <ControlView control={control} />}
          </li>
        ))}
      </ul>
    </figure>
  );
}

// The frame: the caption sits in the top line, the media under it.
function Frame({ media, color }: { media: Media; color: string }) {
  return (
    <figure className="frame">
      <figcaption className="frame__caption">{media.caption}</figcaption>
      <div className="frame__body">
        {media.kind === "demo" && (
          <Demo
            card={{
              id: media.caption,
              hue: "sky",
              color,
              title: "",
              line: "",
              hold: media.hold,
              scenes: media.scenes,
            }}
          />
        )}
        {media.kind === "image" && (
          <img className="frame__image" src={media.src} alt={media.alt} loading="lazy" />
        )}
        {media.kind === "code" && (
          <pre className="frame__code">
            <code>{media.code}</code>
          </pre>
        )}
      </div>
    </figure>
  );
}

function Row({
  feature,
  color,
  technical,
  open,
  onToggle,
}: {
  feature: Feature;
  color: string;
  technical: boolean;
  open: boolean;
  onToggle: (open: boolean) => void;
}) {
  // The right column holds the media. With no media, the next most useful thing moves
  // there: the Settings pane for users, the terminal for agents.
  const hasUsage = (feature.cli?.length ?? 0) + (feature.config?.length ?? 0) > 0;
  const detail = technical
    ? hasUsage && <Usage cli={feature.cli} config={feature.config} />
    : feature.settings && <SettingsPane settings={feature.settings} />;
  const aside = feature.media ? <Frame media={feature.media} color={color} /> : detail || null;
  return (
    <details
      id={feature.id}
      className="row"
      open={open}
      onToggle={(e) => onToggle(e.currentTarget.open)}
    >
      <summary className="row__head">
        <span className="row__name">{feature.name}</span>
        <span className="row__line">{feature.line}</span>
      </summary>
      <div className="row__body" data-solo={aside === null || undefined}>
        <div className="row__text">
          <p className="row__prose">{feature.body}</p>
          {feature.keys && <Keys keys={feature.keys} />}
          {feature.media && detail}
        </div>
        {aside}
      </div>
    </details>
  );
}

// The categories at the side of wide screens. The one you read is marked.
function Rail() {
  const [current, setCurrent] = useState(USER[0].id);

  useEffect(() => {
    const sections = [...document.querySelectorAll<HTMLElement>(".group")];
    const io = new IntersectionObserver(
      (entries) => {
        const hit = entries.find((e) => e.isIntersecting);
        if (hit) setCurrent(hit.target.id);
      },
      { rootMargin: "-80px 0px -70% 0px" },
    );
    for (const s of sections) io.observe(s);
    return () => io.disconnect();
  }, []);

  const list = (categories: Category[]) => (
    <ul className="rail__list">
      {categories.map((c) => (
        <li key={c.id}>
          <a
            className="rail__link"
            href={`#${c.id}`}
            aria-current={c.id === current ? "location" : undefined}
            style={{ "--hue": WINDOWS[c.hue].color } as CSSProperties}
          >
            {c.name}
          </a>
        </li>
      ))}
    </ul>
  );

  return (
    <nav className="rail" aria-label="Categories">
      {list(USER)}
      <a className="rail__part" href="#agents">
        For agents and scripts
      </a>
      {list(AGENT)}
    </nav>
  );
}

export function Features() {
  const [open, setOpen] = useState<Set<string>>(new Set());

  // A link to /features#id opens that row.
  useEffect(() => {
    const id = decodeURIComponent(window.location.hash.slice(1));
    if (!id) return;
    setOpen(new Set([id]));
    requestAnimationFrame(() => document.getElementById(id)?.scrollIntoView({ block: "start" }));
  }, []);

  const toggle = (id: string, isOpen: boolean) => {
    setOpen((prev) => {
      if (prev.has(id) === isOpen) return prev;
      const next = new Set(prev);
      if (isOpen) next.add(id);
      else next.delete(id);
      return next;
    });
    if (isOpen) history.replaceState(null, "", `#${id}`);
    else if (window.location.hash === `#${id}`)
      history.replaceState(null, "", window.location.pathname);
  };

  const group = (c: Category, technical: boolean) => {
    const color = WINDOWS[c.hue].color;
    const Title = technical ? "h3" : "h2";
    return (
      <section key={c.id} id={c.id} className="group" style={{ "--hue": color } as CSSProperties}>
        <Title className="group__title">{c.name}</Title>
        {c.features.map((f) => (
          <Row
            key={f.id}
            feature={f}
            color={color}
            technical={technical}
            open={open.has(f.id)}
            onToggle={(o) => toggle(f.id, o)}
          />
        ))}
      </section>
    );
  };

  return (
    <main className="features">
      <h1 className="sr-only">CatWM features</h1>
      <Rail />
      <div className="features__content">
        {USER.map((c) => group(c, false))}

        <header id="agents" className="part">
          <h2 className="part__title">For agents and scripts</h2>
          <p className="part__line">
            The same app as commands, files and events. Point your agent here, or run catwm docs.
          </p>
        </header>
        {AGENT.map((c) => group(c, true))}
      </div>
    </main>
  );
}
