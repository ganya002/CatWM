import { defineEnv, string } from "void/env";

// The developer roadmap. Without these the public roadmap still works and the developer roadmap
// says that sign-in is not set up.
export const env = defineEnv({
  CLERK_SECRET_KEY: string().optional(),
  CLERK_PUBLISHABLE_KEY: string().optional(),
  // A fine-grained token with read access to the metadata of noxaur/CatWM.
  GITHUB_TOKEN: string().optional(),
  // The secret of the repo webhook that posts issue and PR events to /api/github.
  GITHUB_WEBHOOK_SECRET: string().optional(),
  // The bearer token of /api/roadmap, for scripts and agents.
  ROADMAP_TOKEN: string().optional(),
});
