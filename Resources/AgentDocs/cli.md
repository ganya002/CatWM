# Command line

```sh
CATWM=build/CatWM.app/Contents/MacOS/CatWM   # or /Applications/CatWM.app/Contents/MacOS/CatWM
$CATWM dispatch movefocus l
$CATWM dispatch workspace 3
$CATWM reload
$CATWM dump
```

CatWM links itself as `catwm` in `/usr/local/bin` (or `~/.local/bin` if that is not writable) when the installed app starts. Then `catwm <command>` works from any shell.

The CLI is a client. It sends one request to the running app through a Unix socket (`~/.config/catwm/catwm.sock`, mode `0600`). It prints the answer and exits. The exit code is `0` when the command worked. It is `1` when the app refused the command or does not run. It is `2` when the command line is wrong. Set `CATWM_INSTANCE=<id>` to talk to a separate CatWM instance (socket `~/.config/catwm/instances/<id>/catwm.sock`). Set `CATWM_SOCKET` to use another socket path. It wins over `CATWM_INSTANCE`.

The CLI, the Python, TypeScript and Swift libraries (`Clients/`) and the key binds all use the same command registry. Run `catwm help` for the full list and `catwm help <command>` for the arguments. Add `--json` to print compact JSON.

## Commands

| Command | Effect |
|---|---|
| `<dispatcher> [args]` | run a dispatcher, for example `catwm movefocus left` or `catwm workspace 3`. A bad argument gives an error. See [dispatchers.md](dispatchers.md). |
| `dispatch <name> [args]` | run any dispatcher by name, as a key bind does. Name is case-insensitive. An unknown name gives an error. Bad arguments are ignored silently. |
| `status`, `windows`, `workspaces`, `screens` | print the state as JSON |
| `config.get <key>`, `config.set <key> <value>`, `config.options` | read and change config options. `config.set` writes `catwm.conf` and reloads it. |
| `reload` | re-read `catwm.conf` and rebind keys. Errors go to the log; a HUD shows "Config reloaded" or the error count. |
| `dump` | print the tiling state. The app also writes it to `~/Library/Logs/CatWM.log`. |
| `events [event ...]` | print one JSON line for each event until you stop it. With no names it prints every event. |
| `ping`, `commands` | check the app, or list the commands with their arguments as JSON |
| `docs` | print the folder of bundled agent docs (works without CatWM running; exit 1 if missing) |
| `modefx draw\|ripple\|corners\|none\|all` | preview a window-mode effect |
| `panelfx rise\|pop\|focus\|tile\|draw\|all` | preview a panel animation: opens and closes Overview, then keyboard help |
| `poststyle 0\|1\|2` | diagnostics: how synthetic shortcuts are posted |
| `grabtest` | diagnostics |

`catwm workspaces` includes empty, hidden Desktops from CatWM’s workspace catalog. An empty workspace has `windows: []`; a hidden workspace has `screens: []`.

`exec` and `launch` are **refused** from the socket, because any process of the user could use them. They work only from key binds.

## Events

`catwm events` and the `subscribe` command send these events: `focus.changed`, `window.added`, `window.removed`, `workspace.changed`, `layout.changed`, `tiling.changed`, `mode.changed`, `window.notifications` and `config.reloaded`. Each event is one JSON line: `{"event": "focus.changed", "data": {...}}`. The app sends no events when nobody subscribes.

## Protocol

One JSON object on each line. The app sends `{"hello": {...}}` when you connect. A request is `{"id": 1, "command": "movefocus", "args": {"direction": "left"}}`. The answer is `{"id": 1, "ok": true, "result": ...}` or `{"id": 1, "ok": false, "error": {"code": "invalid_args", "message": "..."}}`. Error codes: `bad_request`, `unknown_command`, `invalid_args`, `forbidden`, `failed`. `Clients/schema.json` lists every command, argument, result and event.

## Reading `dump` output

Each screen lists workspace, layout, ratio and usable rect; each tiled window shows `target` and `actual` frames and `OK` or `MISMATCH`; then floating windows and parked windows (on hidden workspaces).

```sh
$CATWM dump
```

## Launch arguments

Passed to the app itself, e.g. `open build/CatWM.app --args --verbose`:

- `--verbose`: detailed logging (same as `debug-logging = true`).
- `--onboarding`: play the welcome card and keyboard tour regardless of state.
- `--crash-report`: send the newest crash report, to test the upload.
- An unknown argument that starts with `-` prints a usage error and exits 2. It does not start the app. `LaunchFlag` in `App/LaunchArguments.swift` is the list of start flags.
- `practice <pid> [titles]`: internal; the tour's practice windows run as a second copy of the binary. Don't invoke it.

## Build and release (this repo)

```sh
./build.sh                         # builds build/CatWM.app (ad-hoc signed)
open build/CatWM.app
./release.sh "What changed"        # sign, notarize, publish via Amore (+ --channel beta, --critical, --phased-rollout, --draft)
./beta.sh "What changed"           # beta channel, no version bump
```

Ad-hoc signing means each rebuild invalidates the Accessibility grant; see [troubleshooting.md](troubleshooting.md).
