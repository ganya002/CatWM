import { useClerk, useSignIn } from "@clerk/react-router";
import { type DragEvent, type ReactNode, useEffect, useRef, useState } from "react";
import { data, useFetchers, useSubmit } from "react-router";

import { CardPanel, Columns } from "~/roadmap/Roadmap";
import {
  apply,
  type Card,
  type Column,
  type Edit,
  newId,
  parseEdit,
  toForm,
} from "~/roadmap/model";
import { developerAccess } from "~/roadmap/access.server";
import { readCards, writeEdits } from "~/roadmap/store.server";

import type { Route } from "./+types/roadmap.dev";

export async function loader(args: Route.LoaderArgs) {
  const access = await developerAccess(args);
  const cards = access.kind === "in" ? await readCards() : [];
  return { access, cards };
}

export async function action(args: Route.ActionArgs) {
  const access = await developerAccess(args);
  if (access.kind !== "in") throw data("Not a developer", { status: 403 });
  const edit = parseEdit(await args.request.formData());
  if (!edit) throw data("Bad edit", { status: 400 });
  await writeEdits(() => [edit]);
  return null;
}

export default function DeveloperRoadmap({ loaderData }: Route.ComponentProps) {
  const { access, cards } = loaderData;
  switch (access.kind) {
    case "off":
      return (
        <Gate title="Sign-in is not set up">
          Set the Clerk keys and GITHUB_TOKEN. website/README.md lists the steps.
        </Gate>
      );
    case "out":
      return (
        <Gate title="Developer roadmap" action={<SignIn />}>
          Sign in with GitHub. You need access to the CatWM repository.
        </Gate>
      );
    case "denied":
      return (
        <Gate title="No access" action={<SignOut />}>
          {access.login ?? "This account"} is not a collaborator on noxaur/CatWM.
        </Gate>
      );
    case "in":
      return <Roadmap cards={cards} login={access.login} />;
  }
}

type Tab = "roadmap" | "questionable";

const matches = (c: Card, query: string) =>
  [c.title, c.line, c.area, c.note, c.ref, c.id].some((v) => v?.toLowerCase().includes(query));

function Roadmap({ cards: stored, login }: { cards: Card[]; login: string }) {
  const submit = useSubmit();
  const fetchers = useFetchers();
  const [tab, setTab] = useState<Tab>("roadmap");
  const [openId, setOpenId] = useState<string | null>(null);
  const [target, setTarget] = useState<Tab | null>(null);
  const [query, setQuery] = useState("");
  const search = useRef<HTMLInputElement>(null);

  // The roadmap shows each edit while its post runs.
  const cards = fetchers
    .map((f) => f.formData && parseEdit(f.formData))
    .reduce((all, edit) => (edit ? apply(all, edit) : all), stored);
  const saving = fetchers.some((f) => f.state !== "idle");

  const edit = (e: Edit) => void submit(toForm(e), { method: "post", navigate: false });
  const move = (id: string, column: Column, questionable: boolean, before?: string) =>
    edit({ intent: "move", id, column, questionable, before });
  const add = (column: Column, title: string, before?: string) =>
    edit({
      intent: "save",
      card: {
        id: newId(title),
        title,
        line: "",
        area: "The app",
        column,
        questionable: tab === "questionable" || undefined,
      },
      before,
    });

  const q = query.trim().toLowerCase();
  const shown = cards.filter(
    (c) => !!c.questionable === (tab === "questionable") && (!q || matches(c, q)),
  );
  const count = cards.filter((c) => c.questionable).length;
  const open = cards.find((c) => c.id === openId);

  // / finds a card from anywhere on the page.
  useEffect(() => {
    const onKey = (e: globalThis.KeyboardEvent) => {
      const el = e.target as HTMLElement;
      if (e.key !== "/" || el.closest("input, textarea, select")) return;
      e.preventDefault();
      search.current?.focus();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // Drop a card on a tab to flag it as questionable or to keep it.
  const tabDrop = (to: Tab) => ({
    onDragOver: (e: DragEvent) => {
      if (to === tab) return;
      e.preventDefault();
      setTarget(to);
    },
    onDragLeave: () => setTarget(null),
    onDrop: (e: DragEvent) => {
      e.preventDefault();
      setTarget(null);
      const card = cards.find((c) => c.id === e.dataTransfer.getData("text/plain"));
      if (card) move(card.id, card.column, to === "questionable");
    },
  });

  return (
    <main className="roadmap">
      <header className="roadmap__bar">
        <input
          ref={search}
          type="search"
          className="search"
          placeholder="Find a card  /"
          aria-label="Find a card"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Escape") {
              setQuery("");
              e.currentTarget.blur();
            }
          }}
        />
        <div className="tabs" role="tablist" aria-label="Roadmap">
          {(["roadmap", "questionable"] as const).map((t) => (
            <button
              key={t}
              type="button"
              role="tab"
              className="tab"
              aria-selected={tab === t}
              data-target={target === t || undefined}
              onClick={() => setTab(t)}
              {...tabDrop(t)}
            >
              {t === "roadmap" ? "Roadmap" : "Questionable"}
              {t === "questionable" && <span className="tab__count">{count}</span>}
            </button>
          ))}
        </div>
        <span className="roadmap__who">
          <span className="roadmap__saved" aria-live="polite">
            {saving ? "Saving…" : "Saved"}
          </span>
          {login}
          <SignOut />
        </span>
      </header>
      {tab === "questionable" && (
        <p className="roadmap__line">
          These may not be needed, and new cards from GitHub wait here. Drop a card on Roadmap to
          keep it, or open it to remove it.
        </p>
      )}
      <div className="roadmap__body">
        <Columns
          cards={shown}
          selected={open?.id}
          onMove={(id, column, before) => move(id, column, tab === "questionable", before)}
          onOpen={(c) => setOpenId(c.id)}
          onAdd={add}
        />
        {open && (
          <CardPanel key={open.id} card={open} onEdit={edit} onClose={() => setOpenId(null)} />
        )}
      </div>
    </main>
  );
}

function Gate({
  title,
  action,
  children,
}: {
  title: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <main className="gate">
      <div className="gate__card">
        <h1 className="gate__title">{title}</h1>
        <p className="gate__line">{children}</p>
        {action}
      </div>
    </main>
  );
}

function SignIn() {
  const { signIn } = useSignIn();
  const [busy, setBusy] = useState(false);
  return (
    <button
      type="button"
      className="button button--primary"
      disabled={busy}
      onClick={async () => {
        setBusy(true);
        const { error } = await signIn.sso({
          strategy: "oauth_github",
          redirectUrl: "/roadmap/dev",
          redirectCallbackUrl: "/roadmap/sso-callback",
        });
        if (error) setBusy(false);
      }}
    >
      {busy ? "Opening GitHub…" : "Sign in with GitHub"}
    </button>
  );
}

function SignOut() {
  const { signOut } = useClerk();
  return (
    <button
      type="button"
      className="button"
      onClick={() => signOut({ redirectUrl: "/roadmap/dev" })}
    >
      Sign out
    </button>
  );
}
