import { env } from "../../env";
import { githubEdits, type Hook, verifySignature } from "~/roadmap/github";
import { writeEdits } from "~/roadmap/store.server";

import type { Route } from "./+types/api.github";

// The repo webhook: issue and PR events keep the roadmap current. See app/roadmap/github.ts.
export async function action({ request }: Route.ActionArgs) {
  const secret = env.GITHUB_WEBHOOK_SECRET;
  if (!secret) return new Response("The webhook is not set up", { status: 404 });
  const body = await request.text();
  if (!(await verifySignature(secret, body, request.headers.get("X-Hub-Signature-256"))))
    return new Response("Bad signature", { status: 401 });

  const event = request.headers.get("X-GitHub-Event") ?? "";
  const hook = JSON.parse(body) as Hook;
  const changed = await writeEdits((cards) => githubEdits(cards, event, hook));
  return Response.json({ changed });
}
