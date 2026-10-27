import { createHmac } from "node:crypto";

import { describe, expect, test } from "vite-plus/test";

import { githubEdits, type Hook, verifySignature } from "./github";
import { apply, type Card } from "./model";

const card = (id: string, column: Card["column"], extra: Partial<Card> = {}): Card => ({
  id,
  title: id,
  line: "",
  area: "Layouts",
  column,
  ...extra,
});

const run = (cards: Card[], event: string, hook: Hook) =>
  githubEdits(cards, event, hook).reduce(apply, cards);
const where = (cards: Card[], id: string) => {
  const c = cards.find((c) => c.id === id);
  return c && `${c.column}${c.questionable ? "?" : ""}`;
};
const pr = (action: string, body: string, extra: Partial<Hook["pull_request"]> = {}): Hook => ({
  action,
  pull_request: { number: 50, title: "feat(tabs): stretch the strip", body, ...extra },
});

describe("githubEdits", () => {
  test("the roadmap label adds a questionable card once, with area and title from the commit", () => {
    const hook: Hook = {
      action: "labeled",
      label: { name: "roadmap" },
      issue: { number: 7, title: "fix(switcher): faster search", labels: [{ name: "roadmap" }] },
    };
    const once = run([], "issues", hook);
    expect(once).toEqual([
      expect.objectContaining({
        id: "gh-7",
        title: "Faster search",
        area: "Overview and switcher",
        column: "idea",
        questionable: true,
        ref: "#7",
      }),
    ]);
    expect(run(once, "issues", hook)).toEqual(once);
  });

  test("a labelled PR adds its card in progress", () => {
    const after = run([], "pull_request", pr("opened", "", { labels: [{ name: "roadmap" }] }));
    expect(where(after, "gh-50")).toBe("doing?");
  });

  test("a PR moves the cards it links: open, merge and close", () => {
    const cards = [
      card("by-issue", "planned", { ref: "#12" }),
      card("by-id", "idea"),
      card("other", "idea", { ref: "#13" }),
    ];
    const body = "Some text.\n\nCloses #12\nRoadmap: by-id";
    const opened = run(cards, "pull_request", pr("opened", body));
    expect([where(opened, "by-issue"), where(opened, "by-id"), where(opened, "other")]).toEqual([
      "doing",
      "doing",
      "idea",
    ]);
    const merged = run(opened, "pull_request", pr("closed", body, { merged: true }));
    expect([where(merged, "by-issue"), where(merged, "by-id")]).toEqual(["done", "done"]);
    const dropped = run(opened, "pull_request", pr("closed", body, { merged: false }));
    expect([where(dropped, "by-issue"), where(dropped, "by-id")]).toEqual(["planned", "planned"]);
  });

  test("an open PR does not move a shipped card back", () => {
    const cards = [card("old", "done", { ref: "#12" })];
    expect(githubEdits(cards, "pull_request", pr("opened", "Fixes #12"))).toEqual([]);
  });

  test("issue labels and close reasons", () => {
    const cards = [card("a", "idea", { ref: "#7" })];
    const issue = { number: 7, title: "A" };
    const planned = run(cards, "issues", { action: "labeled", label: { name: "planned" }, issue });
    expect(where(planned, "a")).toBe("planned");
    const dropped = run(planned, "issues", {
      action: "closed",
      issue: { ...issue, state_reason: "not_planned" },
    });
    expect(where(dropped, "a")).toBe("planned?");
    expect(githubEdits(cards, "issues", { action: "closed", issue })).toEqual([]);
  });

  test("other events change nothing", () => {
    expect(githubEdits([card("a", "idea", { ref: "#1" })], "push", { action: "" })).toEqual([]);
  });
});

test("verifySignature accepts GitHub's signature and rejects others", async () => {
  const body = '{"action":"opened"}';
  const sig = `sha256=${createHmac("sha256", "s3cret").update(body).digest("hex")}`;
  expect(await verifySignature("s3cret", body, sig)).toBe(true);
  expect(await verifySignature("wrong", body, sig)).toBe(false);
  expect(await verifySignature("s3cret", `${body} `, sig)).toBe(false);
  expect(await verifySignature("s3cret", body, null)).toBe(false);
});
