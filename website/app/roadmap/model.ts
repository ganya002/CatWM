import type { Hue } from "~/catwm/script";

export const COLUMNS = [
  { id: "idea", name: "Ideas" },
  { id: "planned", name: "Planned" },
  { id: "doing", name: "In progress" },
  { id: "done", name: "Shipped" },
] as const;

export type Column = (typeof COLUMNS)[number]["id"];

// The areas follow the categories of the features page, with their hues.
export const AREAS: Record<string, Hue> = {
  "Window mode": "sky",
  "Focus and move": "lemon",
  Layouts: "magenta",
  Workspaces: "lime",
  Displays: "sky",
  "Floating and fullscreen": "lemon",
  Tabs: "magenta",
  "Overview and switcher": "lime",
  "Saved workspaces": "sky",
  "Look and motion": "lemon",
  "Keys and settings": "magenta",
  "The app": "sky",
  Automation: "lime",
};

// A questionable card keeps its column. It shows only in the Questionable tab of the developer
// roadmap until a developer keeps it or removes it. The note and the ref show only to developers.
export type Card = {
  id: string;
  title: string;
  line: string;
  area: string;
  column: Column;
  questionable?: boolean;
  note?: string;
  ref?: string;
};

export type Edit =
  | { intent: "move"; id: string; column: Column; questionable: boolean; before?: string }
  | { intent: "save"; card: Card; before?: string }
  | { intent: "remove"; id: string };

const isColumn = (v: unknown): v is Column => COLUMNS.some((c) => c.id === v);

// Reads an edit from the form that the developer roadmap posts. Returns null for a bad form.
export function parseEdit(form: FormData): Edit | null {
  const text = (k: string) => {
    const v = form.get(k);
    return typeof v === "string" ? v.trim() : "";
  };
  const column = text("column");
  const questionable = form.get("questionable") === "1";
  switch (text("intent")) {
    case "move":
      if (!text("id") || !isColumn(column)) return null;
      return {
        intent: "move",
        id: text("id"),
        column,
        questionable,
        before: text("before") || undefined,
      };
    case "save": {
      const title = text("title");
      if (!text("id") || !title || !isColumn(column) || !(text("area") in AREAS)) return null;
      return {
        intent: "save",
        card: {
          id: text("id"),
          title,
          line: text("line"),
          area: text("area"),
          column,
          questionable: questionable || undefined,
          note: text("note") || undefined,
          ref: text("ref") || undefined,
        },
        before: text("before") || undefined,
      };
    }
    case "remove":
      return text("id") ? { intent: "remove", id: text("id") } : null;
  }
  return null;
}

export function toForm(edit: Edit): Record<string, string> {
  switch (edit.intent) {
    case "move":
      return {
        intent: "move",
        id: edit.id,
        column: edit.column,
        questionable: edit.questionable ? "1" : "0",
        before: edit.before ?? "",
      };
    case "save":
      return {
        intent: "save",
        ...edit.card,
        questionable: edit.card.questionable ? "1" : "0",
        note: edit.card.note ?? "",
        ref: edit.card.ref ?? "",
        before: edit.before ?? "",
      };
    case "remove":
      return { intent: "remove", id: edit.id };
  }
}

export const newId = (title: string) =>
  `${title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")}-${Date.now().toString(36)}`;

// Applies one edit. The server stores the result, and the roadmap shows it while the post runs.
export function apply(cards: Card[], edit: Edit): Card[] {
  switch (edit.intent) {
    case "remove":
      return cards.filter((c) => c.id !== edit.id);
    case "save": {
      if (!cards.some((c) => c.id === edit.card.id)) {
        const at = edit.before ? cards.findIndex((c) => c.id === edit.before) : -1;
        if (at === -1) return [...cards, edit.card];
        return [...cards.slice(0, at), edit.card, ...cards.slice(at)];
      }
      return cards.map((c) => (c.id === edit.card.id ? edit.card : c));
    }
    case "move": {
      const card = cards.find((c) => c.id === edit.id);
      if (!card) return cards;
      const rest = cards.filter((c) => c.id !== edit.id);
      const moved = { ...card, column: edit.column, questionable: edit.questionable || undefined };
      const at = edit.before ? rest.findIndex((c) => c.id === edit.before) : -1;
      if (at === -1) return [...rest, moved];
      return [...rest.slice(0, at), moved, ...rest.slice(at)];
    }
  }
}

// The public roadmap: no questionable cards, no notes and no refs to the private repo.
export const publicCards = (cards: Card[]): Card[] =>
  cards
    .filter((c) => !c.questionable)
    .map(({ id, title, line, area, column }) => ({ id, title, line, area, column }));
