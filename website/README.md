# Ouch website

Landing page for Ouch: the demo video, "Public release soon.", and an email signup.

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
