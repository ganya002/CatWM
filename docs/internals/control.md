# Control: the CLI, the socket and the libraries

One registry feeds every way to control CatWM from outside the app. Key binds, the `catwm` CLI, the socket and the language libraries all run the same commands. `WindowActions.all` (`Sources/CatWMKit/Actions/`) is the only list of dispatchers. The registry, `WindowManager.dispatch`, the bind picker, `Clients/schema.json` and the generated clients all read it, so a new dispatcher is one `WindowAction` and a build. Queries and config commands are `Command`s in `Control/`.

`ControlServer` reads on a background queue and runs each command on the main queue, in order. It refuses a socket path longer than `sun_path` (104 bytes) instead of cutting it. A client that falls 1 MB behind is dropped. `EventBus` diffs a state snapshot against the last one only while someone subscribes, so events cost nothing with no subscriber.

## Access

- `public`: in the CLI, the schema and the libraries.
- `dev`: works over the socket but stays out of the schema.
- `keybindOnly`: refused over the socket (`exec`, `launch`). Any process of the user can connect, so a command that runs code must not be public.

## Instances

`CATWM_INSTANCE=<id>` starts a separate CatWM with its own config folder, log, support folders and defaults suite. `Instance` (`Sources/CatWMKit/App/Instance.swift`) owns every path, and `Tools/check-style.sh` rejects `UserDefaults.standard`. A bad id stops CatWM with exit code 2 instead of falling back to the default instance, because the default instance quits the user's CatWM.

Each instance writes `catwm.pid`. At start, the default instance stops every other `local.catwm` process except the pids in `instances/*/catwm.pid`, and `build.sh` does the same. A named instance skips everything that would touch the user's setup: the login item, the `catwm` link, the updater, reports, onboarding, tips, What's New and migrations. It keeps the bundle ID and signature, so the app's macOS permissions still apply.

## Window scope

`CATWM_SCOPE=pids:<pid>,…[;display:<UUID>]` limits a named instance to those pids, and to that display if given. A bad or empty value stops CatWM with exit code 2, and so does a named instance with no scope unless you pass `--unscoped`. A bad value must never mean "all windows".

A scoped instance must not change anything outside its scope. `WindowScanner` filters other pids before the manager sees them. Desktops are off, templates refuse to open, and `GlobalInput` starts no event taps, Caps Lock change, pointer moves or focus window. `CATWM_KEYS=on` brings back the key tap. `WindowScope.refusedCommands` blocks commands that reach outside the scope: they change Desktops, move the pointer, show panels over every app, or run commands. Every command must be in `allowedCommands` or `refusedCommands`, and a test fails otherwise. Add a new restriction in `WindowScope.restrict`, `GlobalInput` or those lists, never at the call site. A focus command can still activate the target's app, which can raise that app's other windows.

The user's CatWM must also stay off the scoped windows. A scoped instance writes `scope` (owner pid, then scope) in its folder, and an unscoped instance reads `instances/*/scope` and skips the claimed pids. It re-reads only when the `instances` folder's modification time changes. A write inside `instances/<id>/` doesn't touch that time, so `writeClaim` writes in `instances` and renames into place, and `removeClaim` moves the file back out before deleting it. `ScopeClaims.watch` watches the folder and each owner pid with `DispatchSource`s, so a claim left by a killed owner (even `kill -9`) triggers a scan at once. When a pid becomes claimed, the user's CatWM drops its windows, its observer and its queued writes. One AX write that has already started can still land. The claimed display isn't excluded, so the user's CatWM still tiles its own windows there.

## Libraries

`Tools/generate-clients.py` writes the Python, TypeScript and Swift clients from `Clients/schema.json`. `Clients/python/catwm/testing.py` is hand-written. The wire protocol is in `Resources/AgentDocs/cli.md`.
