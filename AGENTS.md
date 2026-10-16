Building the project

```text
./build.sh 
```

For fast rebuilds while you work, use `./build.sh --dev` (debug build, a few seconds per rebuild). Do not ship a `--dev` build.

# Verifying

### Requires visual verification

build the project
output `open build/ouch.app`
state verifying needs

# Cloud Agents

Cloud Agent VMs are Linux. `./build.sh` needs the macOS SDK (`swift`, `xcrun`, `codesign`, `PlistBuddy`) and cannot produce `build/ouch.app` here.

The site in `website/` is the app that runs in this environment. React Router requires Node greater than 22.22. `/exec-daemon/node` is older and comes first on `PATH`; use `~/.nvm/versions/node/v22.23.3` (the install script links it ahead of `/exec-daemon/node`). pnpm is 12.11.2, pinned by `website/pnpm-lock.yaml`.

From `website/`:

- `pnpm install --frozen-lockfile`
- `pnpm exec react-router typegen` before `vp check` (`.react-router/` is gitignored)
- `pnpm exec vp check`
- `pnpm exec vp build`
- Dev server, started on boot: `pnpm exec vp dev --host 0.0.0.0 --port 5173` at http://127.0.0.1:5173/

The notify-me form stores emails in local Void KV. It does not need Cloudflare credentials. `report-relay/` files Linear issues and needs `LINEAR_API_KEY`; do not deploy it from a Cloud Agent.
