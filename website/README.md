# CatWM website

Landing page for CatWM: the brand lockup over four tiled windows, a scroll story that plays the real
window manager behaviour (window mode, workspaces, layouts, saved workspaces, overview, CLI), the
install command and an email signup.

`app/catwm/layout.ts` is a port of the Swift layout and neighbour code. `app/catwm/script.ts` holds the
state, the dispatcher reducers and the scripted steps. `app/catwm/Story.tsx` builds one GSAP timeline per
step from them, at the animator's real timing (0.18 s, cubic ease-out). Change the Swift code and the
port together.

- React Router 8 (framework mode, SSR)
- Vite+ (`vp`) for dev, build, format, lint, and type checks
- Void for deployment to Cloudflare Workers. Signups go to Void KV under the `signups:` prefix.

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

```sh
vp exec void connect --platform cloudflare
vp exec void deploy
```

`public/demo.mp4` is a 1920 px H.264 re-encode of the source demo. Workers static assets must be 25 MiB or smaller per file.
