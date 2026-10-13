# Command line

```sh
OUCH=build/ouch.app/Contents/MacOS/ouch   # or /Applications/Ouch.app/Contents/MacOS/ouch
$OUCH dispatch movefocus l
$OUCH dispatch workspace 3
$OUCH reload
$OUCH dump
```

Like `hyprctl`. The command is sent to the running instance through a distributed notification (`local.ouch.command`), and the process exits immediately with status 0. Nothing is printed except for `dump`.

## Commands

| Command | Effect |
|---|---|
| `dispatch <name> [args]` | run a dispatcher, same as a keybind would. See [dispatchers.md](dispatchers.md). Name is case-insensitive. |
| `docs` | print the folder of bundled agent docs (works without Ouch running; exit 1 if missing) |
| `reload` | re-read `ouch.conf` and rebind keys. Errors go to the log; a HUD shows "Config reloaded" or the error count. |
| `dump` | write tiling state to `~/Library/Logs/ouch.log` (prints only the log path) |
| `modefx draw\|ripple\|corners\|none\|all` | preview a window-mode effect |
| `poststyle 0\|1\|2` | diagnostics: how synthetic shortcuts are posted |
| `grabtest` | diagnostics |

`dispatch exec …` is **refused** from the CLI (any process could post that notification). `exec` works only from keybinds.

`docs` is the exception to "sent to the running app": it reads the bundle and prints directly.

Anything else, or a missing app, fails silently. Verify by reading the log.

## Reading `dump` output

Each screen lists workspace, layout, ratio and usable rect; each tiled window shows `target` and `actual` frames and `OK` or `MISMATCH`; then floating windows and parked windows (on hidden workspaces).

```sh
$OUCH dump && tail -n 40 ~/Library/Logs/ouch.log
```

## Launch arguments

Passed to the app itself, e.g. `open build/ouch.app --args --verbose`:

- `--verbose`: detailed logging (same as `debug-logging = true`).
- `--onboarding`: play the welcome card and keyboard tour regardless of state.
- `practice <pid> [titles]`: internal; the tour's practice windows run as a second copy of the binary. Don't invoke it.

## Build and release (this repo)

```sh
./build.sh                         # builds build/ouch.app (ad-hoc signed)
open build/ouch.app
./release.sh "What changed"        # sign, notarize, publish via Amore (+ --channel beta, --critical, --phased-rollout, --draft)
./beta.sh "What changed"           # beta channel, no version bump
```

Ad-hoc signing means each rebuild invalidates the Accessibility grant; see [troubleshooting.md](troubleshooting.md).
