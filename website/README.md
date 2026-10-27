# CatWM website

Landing page for CatWM. The first screen is four windows in a pile with the brand lockup and one
install button on them; the keys below (N, Shift H J K L, F, Shift T) run the real window manager
behaviour on the pile, and the page presses them itself until the visitor does. Below it, four
cards in the four hues slide over the stage, one feature each, with a small display that loops a
few moves. The last card repeats the install button.

`app/catwm/layout.ts` is a port of the Swift layout and neighbour code. `app/catwm/script.ts` holds the
stage state, the dispatcher reducers behind each key and the attract sequence, and `app/catwm/cards.ts`
the cards and their scenes. `app/catwm/Stage.tsx` moves the windows with GSAP at the animator's real
timing (0.18 s, cubic ease-out). Change the Swift code and the port together.

## Roadmap

`/roadmap` is the public roadmap, as a kanban board: Ideas, Planned, In progress and Shipped. `/roadmap/dev` is the
developer roadmap. It adds the Questionable tab, the notes and the issue refs, and a developer can
drag, add, edit and remove cards. Drop a card on a tab to flag it as questionable or to keep it.

The roadmap is one JSON value in Workers KV (`roadmap`). `app/roadmap/seed.ts` is the first roadmap and
shows only while KV is empty. The developer roadmap writes the whole value on each edit, so two
developers who edit within a minute from different regions can lose one edit (KV is eventually
consistent).

A developer signs in with GitHub through Clerk and must be a collaborator on `noxaur/CatWM`. The
answer stays in KV for ten minutes. Clerk runs only on the developer routes.

To turn the developer roadmap on:

1. In Clerk, make GitHub the only sign-in method. A production instance needs its own GitHub OAuth app and the Clerk DNS records for `catwm.perwko.com`.
2. Make a fine-grained GitHub token with read access to the metadata of `noxaur/CatWM`.
3. Set the three Worker secrets: `wrangler secret put CLERK_PUBLISHABLE_KEY`, `CLERK_SECRET_KEY` and `GITHUB_TOKEN` (add `--name ouch-website`). For `vp dev`, put the same names in `.env`.

Without them the public roadmap works and `/roadmap/dev` says that sign-in is not set up.

### GitHub and agents

GitHub keeps the roadmap current through a repo webhook (`app/roadmap/github.ts`):

- The `roadmap` label on an issue or a PR adds a card, flagged questionable, so it waits in the Questionable tab until a developer keeps it.
- A PR moves the cards it links with `Closes #12` (or Fixes, Resolves), `Roadmap: <card id>`, or a card whose ref is the PR. Opening moves them to In progress, merging to Shipped, and closing without a merge back to Planned.
- The `planned` label moves an issue card to Planned. An issue closed as not planned becomes questionable.

To turn it on, add a webhook in the repo settings: payload URL `https://catwm.perwko.com/api/github`, content type `application/json`, a random secret, and only the Issues and Pull requests events. Set the same secret with `wrangler secret put GITHUB_WEBHOOK_SECRET`.

Scripts and agents read and edit the roadmap at `/api/roadmap` with a bearer token: `wrangler secret put ROADMAP_TOKEN`. The `roadmap` skill (`.agents/skills/roadmap/`) tells agents how to use the labels, the PR lines and the API.

We left out an MCP server, Linear, Notion, Slack and public votes: agents already use `gh` and `curl`, a second tracker means sync conflicts, and the app's Send Feedback sheet already takes user input.

## Stack

- React Router 8 (framework mode, SSR)
- Vite+ (`vp`) for dev, build, format, lint, and type checks
- Wrangler for deployment to Cloudflare Workers. `void.config.ts` still generates the Worker config at build time.

## Develop

```sh
vp install
vp dev
```

## Check and build

```sh
vp check
vp test
vp build
```

## Deploy

The `deploy-website` GitHub Actions workflow deploys every push to `main` that touches `website/`.
It needs a `CLOUDFLARE_API_TOKEN` repository secret with Workers Scripts and Workers KV Storage
edit access on the account, and Workers Routes and DNS edit access on the `perwko.com` zone.

The workflow runs `vp build`, then `wrangler deploy --config build/server/wrangler.json`. `void deploy` is not used: its version tracking failed after the upload and left the Worker rolled back.

To deploy by hand:

```sh
wrangler login
pnpm deploy
```

`public/demo.mp4` is a 1920 px H.264 re-encode of the source demo. Workers static assets must be 25 MiB or smaller per file.
