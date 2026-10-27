import { env } from "../../env";
import { parseEdit } from "~/roadmap/model";
import { readCards, writeEdits } from "~/roadmap/store.server";

import type { Route } from "./+types/api.roadmap";

// The roadmap for scripts and agents, with the ROADMAP_TOKEN as a bearer token.
// GET lists every card. POST takes the same fields as the developer roadmap:
// curl -H "Authorization: Bearer $ROADMAP_TOKEN" -F intent=move -F id=… -F column=doing …
async function allowed(request: Request) {
  const token = env.ROADMAP_TOKEN;
  const given = /^Bearer (.+)$/.exec(request.headers.get("Authorization") ?? "")?.[1];
  if (!token || !given) return false;
  // Compare digests, so the time of the compare does not depend on the token.
  const digest = async (s: string) =>
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))).join();
  return (await digest(token)) === (await digest(given));
}

export async function loader({ request }: Route.LoaderArgs) {
  if (!(await allowed(request))) return new Response("Unauthorized", { status: 401 });
  return Response.json({ cards: await readCards() });
}

export async function action({ request }: Route.ActionArgs) {
  if (!(await allowed(request))) return new Response("Unauthorized", { status: 401 });
  const edit = parseEdit(await request.formData());
  if (!edit) return new Response("Bad edit", { status: 400 });
  await writeEdits(() => [edit]);
  return Response.json({ ok: true });
}
