import { Columns } from "~/roadmap/Roadmap";
import { publicCards } from "~/roadmap/model";
import { readCards } from "~/roadmap/store.server";

import type { Route } from "./+types/roadmap";

const DESCRIPTION = "What CatWM has shipped, what is in progress and what comes next.";

export function meta() {
  return [
    { title: "CatWM roadmap" },
    { name: "description", content: DESCRIPTION },
    { name: "theme-color", content: "#000000" },
  ];
}

export async function loader() {
  return { cards: publicCards(await readCards()) };
}

export function headers() {
  return { "Cache-Control": "public, max-age=60" };
}

export default function RoadmapPage({ loaderData }: Route.ComponentProps) {
  return (
    <main className="roadmap">
      <header className="roadmap__head">
        <h1 className="roadmap__title">Roadmap</h1>
        <p className="roadmap__line">{DESCRIPTION}</p>
      </header>
      <Columns cards={loaderData.cards} />
    </main>
  );
}
