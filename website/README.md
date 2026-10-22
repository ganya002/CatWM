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

- React Router 8 (framework mode, SSR)
- Vite+ (`vp`) for dev, build, format, lint, and type checks
- Void for deployment to Cloudflare Workers.

## Develop

```sh
vp install
vp dev
```

## Check and build

```sh
vp check
vp build
```

## Deploy

The `deploy-website` GitHub Actions workflow deploys every push to `main` that touches `website/`.
It needs a `CLOUDFLARE_API_TOKEN` repository secret with Workers Scripts and Workers KV Storage
edit access on the account, and Workers Routes and DNS edit access on the `perwko.com` zone.

To deploy by hand:

```sh
vp exec void connect --platform cloudflare
vp exec void deploy
```

`public/demo.mp4` is a 1920 px H.264 re-encode of the source demo. Workers static assets must be 25 MiB or smaller per file.
