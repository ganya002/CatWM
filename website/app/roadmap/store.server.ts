import { kv } from "void/kv";

import { apply, type Card, type Edit } from "./model";
import { SEED } from "./seed";

const KEY = "roadmap";

export async function readCards(): Promise<Card[]> {
  return (await kv.get<Card[]>(KEY)) ?? SEED;
}

// Reads the roadmap once, applies the edits that `make` returns and writes once.
// Returns the number of edits.
export async function writeEdits(make: (cards: Card[]) => Edit[]): Promise<number> {
  const cards = await readCards();
  const edits = make(cards);
  if (edits.length > 0) await kv.put(KEY, edits.reduce(apply, cards));
  return edits.length;
}
