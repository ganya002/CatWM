import { describe, expect, test } from "vite-plus/test";

import { AREAS, apply, type Card, type Edit, parseEdit, publicCards, toForm } from "./model";
import { SEED } from "./seed";

const card = (id: string, column: Card["column"], extra: Partial<Card> = {}): Card => ({
  id,
  title: id,
  line: "",
  area: "Layouts",
  column,
  ...extra,
});

const ids = (cards: Card[]) => cards.map((c) => `${c.id}:${c.column}${c.questionable ? "?" : ""}`);

const form = (edit: Edit) => {
  const f = new FormData();
  for (const [k, v] of Object.entries(toForm(edit))) f.set(k, v);
  return f;
};

describe("apply", () => {
  const cards = [card("a", "idea"), card("b", "idea"), card("c", "done")];

  test("moves a card before another card", () => {
    const moved = apply(cards, {
      intent: "move",
      id: "c",
      column: "idea",
      questionable: false,
      before: "b",
    });
    expect(ids(moved)).toEqual(["a:idea", "c:idea", "b:idea"]);
  });

  test("moves a card to the end of a column with no before", () => {
    const moved = apply(cards, { intent: "move", id: "a", column: "done", questionable: false });
    expect(ids(moved)).toEqual(["b:idea", "c:done", "a:done"]);
  });

  test("flags and keeps a questionable card in its column", () => {
    const flagged = apply(cards, { intent: "move", id: "b", column: "idea", questionable: true });
    expect(ids(flagged)).toContain("b:idea?");
    const kept = apply(flagged, { intent: "move", id: "b", column: "idea", questionable: false });
    expect(ids(kept)).toContain("b:idea");
  });

  test("saves a new card, replaces an existing card and removes a card", () => {
    const added = apply(cards, { intent: "save", card: card("d", "planned") });
    expect(ids(added)).toEqual(["a:idea", "b:idea", "c:done", "d:planned"]);
    const edited = apply(added, { intent: "save", card: card("a", "doing", { title: "A" }) });
    expect(edited[0]).toMatchObject({ id: "a", column: "doing", title: "A" });
    expect(ids(apply(edited, { intent: "remove", id: "b" }))).toEqual([
      "a:doing",
      "c:done",
      "d:planned",
    ]);
  });

  test("puts a new card before another card", () => {
    const added = apply(cards, { intent: "save", card: card("d", "idea"), before: "a" });
    expect(ids(added)).toEqual(["d:idea", "a:idea", "b:idea", "c:done"]);
  });
});

describe("parseEdit", () => {
  test("reads back every edit that the roadmap posts", () => {
    const edits: Edit[] = [
      { intent: "move", id: "a", column: "planned", questionable: true, before: "b" },
      { intent: "move", id: "a", column: "done", questionable: false },
      { intent: "save", card: card("a", "idea", { questionable: true, note: "why", ref: "#1" }) },
      { intent: "save", card: card("b", "done"), before: "a" },
      { intent: "remove", id: "a" },
    ];
    for (const edit of edits) expect(parseEdit(form(edit))).toEqual(edit);
  });

  test("rejects an unknown column or area", () => {
    expect(
      parseEdit(form({ intent: "save", card: card("a", "idea", { area: "Nope" }) })),
    ).toBeNull();
    const f = form({ intent: "move", id: "a", column: "idea", questionable: false });
    f.set("column", "trash");
    expect(parseEdit(f)).toBeNull();
  });
});

test("the public roadmap has no questionable cards, notes or refs", () => {
  const cards = [
    card("a", "idea", { note: "n", ref: "#1" }),
    card("b", "done", { questionable: true }),
  ];
  expect(publicCards(cards)).toEqual([card("a", "idea")]);
});

test("every seed card has a unique id and a known area", () => {
  expect(new Set(SEED.map((c) => c.id)).size).toBe(SEED.length);
  for (const c of SEED) expect(Object.keys(AREAS)).toContain(c.area);
});
