import { ClerkProvider } from "@clerk/react-router";
import { rootAuthLoader } from "@clerk/react-router/server";
import { Outlet } from "react-router";

import { clerkReady, developerMiddleware } from "~/roadmap/access.server";

import type { Route } from "./+types/developer";

// The developer pages: Clerk runs here and nowhere else.
export const middleware: Route.MiddlewareFunction[] = [developerMiddleware];

export function loader(args: Route.LoaderArgs) {
  return clerkReady() ? rootAuthLoader(args) : null;
}

export function meta() {
  return [{ title: "CatWM developer roadmap" }, { name: "robots", content: "noindex" }];
}

export default function Developer({ loaderData }: Route.ComponentProps) {
  if (!loaderData) return <Outlet />;
  return (
    <ClerkProvider loaderData={loaderData}>
      <Outlet />
    </ClerkProvider>
  );
}
