import { clerkClient, clerkMiddleware, getAuth } from "@clerk/react-router/server";
import type { LoaderFunctionArgs, MiddlewareFunction } from "react-router";
import { env } from "../../env";
import { kv } from "void/kv";

const REPO = "noxaur/CatWM";

export type Access =
  | { kind: "off" }
  | { kind: "out" }
  | { kind: "denied"; login: string | null }
  | { kind: "in"; login: string };

const keys = () =>
  env.CLERK_SECRET_KEY && env.CLERK_PUBLISHABLE_KEY
    ? { secretKey: env.CLERK_SECRET_KEY, publishableKey: env.CLERK_PUBLISHABLE_KEY }
    : null;

export const clerkReady = () => keys() !== null;

// Clerk runs only on the developer routes, so the other pages do no auth work.
export const developerMiddleware: MiddlewareFunction<Response> = (args, next) => {
  const k = keys();
  return k ? clerkMiddleware(k)(args, next) : next();
};

// A developer is a signed-in GitHub user who is a collaborator on the repo.
// The answer stays in KV for ten minutes, so a page load does not call Clerk and GitHub.
export async function developerAccess(args: LoaderFunctionArgs): Promise<Access> {
  const k = keys();
  if (!k) return { kind: "off" };
  const { userId } = await getAuth(args);
  if (!userId) return { kind: "out" };

  const cacheKey = `roadmap-access:${userId}`;
  let found = await kv.get<{ login: string | null; ok: boolean }>(cacheKey);
  if (!found) {
    const user = await clerkClient(args, k).users.getUser(userId);
    const login =
      user.externalAccounts.find((a) => a.provider === "oauth_github")?.username || null;
    found = { login, ok: login !== null && (await isCollaborator(login)) };
    await kv.put(cacheKey, found, { ttl: 600 });
  }
  return found.ok && found.login
    ? { kind: "in", login: found.login }
    : { kind: "denied", login: found.login };
}

async function isCollaborator(login: string): Promise<boolean> {
  if (!env.GITHUB_TOKEN) throw new Error("GITHUB_TOKEN is not set");
  const res = await fetch(
    `https://api.github.com/repos/${REPO}/collaborators/${encodeURIComponent(login)}`,
    {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "User-Agent": "catwm-website",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    },
  );
  if (res.status === 204) return true;
  if (res.status === 404) return false;
  throw new Error(`GitHub collaborator check failed: ${res.status}`);
}
