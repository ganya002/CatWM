import { AREAS, type Card, type Column, type Edit } from "./model";

// GitHub keeps the roadmap current. The `roadmap` label adds a card for an issue or a PR, as
// questionable, so a developer reviews it before the public sees it. A PR moves the cards it
// links: "Closes #12" (or Fixes, Resolves), "Roadmap: <card id>", or a card whose ref is the PR.
// Open moves them to In progress, merge to Shipped, close without merge back to Planned.
// An issue with the `planned` label moves to Planned, and one closed as not planned
// becomes questionable.

type Label = { name: string };
type Item = {
  number: number;
  title: string;
  body?: string | null;
  labels?: Label[];
  state_reason?: string | null;
  merged?: boolean;
};
export type Hook = { action: string; issue?: Item; pull_request?: Item; label?: Label };

const ROADMAP = "roadmap";
const PLANNED = "planned";

// The conventional-commit scope picks the area. Other scopes go to The app.
const SCOPES: Record<string, string> = {
  layout: "Layouts",
  layouts: "Layouts",
  tiling: "Layouts",
  workspaces: "Workspaces",
  desktops: "Workspaces",
  spaces: "Workspaces",
  displays: "Displays",
  focus: "Focus and move",
  floating: "Floating and fullscreen",
  fullscreen: "Floating and fullscreen",
  tabs: "Tabs",
  switcher: "Overview and switcher",
  overview: "Overview and switcher",
  sort: "Overview and switcher",
  templates: "Saved workspaces",
  session: "Saved workspaces",
  animation: "Look and motion",
  motion: "Look and motion",
  theme: "Look and motion",
  keys: "Keys and settings",
  settings: "Keys and settings",
  config: "Keys and settings",
  onboarding: "Keys and settings",
  "window-mode": "Window mode",
  hud: "Window mode",
  cli: "Automation",
  control: "Automation",
  clients: "Automation",
};

function card(item: Item, column: Column): Card {
  const commit = /^\w+(?:\(([^)]*)\))?!?:\s*(.+)$/.exec(item.title);
  const title = commit ? commit[2] : item.title;
  const area = SCOPES[commit?.[1]?.toLowerCase() ?? ""];
  return {
    id: `gh-${item.number}`,
    title: title.charAt(0).toUpperCase() + title.slice(1),
    line: "",
    area: area && area in AREAS ? area : "The app",
    column,
    questionable: true,
    note: "Added from GitHub. Keep it to show it on the public roadmap.",
    ref: `#${item.number}`,
  };
}

// The refs and card ids that a PR body names.
function links(body: string | null | undefined): string[] {
  const text = body ?? "";
  const refs = [...text.matchAll(/\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)/gi)];
  const ids = [...text.matchAll(/^Roadmap:\s*(\S+)/gim)];
  return [...refs.map((m) => `#${m[1]}`), ...ids.map((m) => m[1])];
}

export function githubEdits(cards: Card[], event: string, hook: Hook): Edit[] {
  const pr = event === "pull_request" ? hook.pull_request : undefined;
  const item = event === "issues" ? hook.issue : pr;
  if (!item) return [];
  const ref = `#${item.number}`;
  const edits: Edit[] = [];

  const labelled =
    (hook.action === "opened" || hook.action === "labeled") &&
    (item.labels ?? []).some((l) => l.name === ROADMAP);
  if (labelled && !cards.some((c) => c.ref === ref)) {
    const added = card(item, pr ? (pr.merged ? "done" : "doing") : "idea");
    edits.push({ intent: "save", card: added });
    cards = [...cards, added];
  }

  const named = pr ? links(pr.body) : [];
  const linked = cards.filter(
    (c) => c.ref === ref || named.includes(c.id) || (c.ref && named.includes(c.ref)),
  );
  const move = (column: Column, when: (c: Card) => boolean = (c) => c.column !== column) => {
    for (const c of linked.filter(when))
      edits.push({ intent: "move", id: c.id, column, questionable: !!c.questionable });
  };

  if (pr) {
    if (["opened", "reopened", "ready_for_review"].includes(hook.action))
      move("doing", (c) => c.column === "idea" || c.column === "planned");
    else if (hook.action === "closed" && pr.merged) move("done");
    else if (hook.action === "closed") move("planned", (c) => c.column === "doing");
  } else if (hook.action === "labeled" && hook.label?.name === PLANNED) {
    move("planned", (c) => c.column === "idea");
  } else if (hook.action === "closed" && item.state_reason === "not_planned") {
    for (const c of linked.filter((c) => !c.questionable))
      edits.push({ intent: "move", id: c.id, column: c.column, questionable: true });
  }
  return edits;
}

// GitHub signs each delivery with HMAC SHA-256 of the raw body: "sha256=<hex>".
export async function verifySignature(secret: string, body: string, header: string | null) {
  const hex = header?.startsWith("sha256=") ? header.slice(7) : "";
  if (!/^[0-9a-f]{64}$/.test(hex)) return false;
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const sig = new Uint8Array(hex.match(/../g)!.map((b) => parseInt(b, 16)));
  return crypto.subtle.verify("HMAC", key, sig, enc.encode(body));
}
