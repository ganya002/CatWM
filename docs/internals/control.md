# Control: the CLI, the socket and the libraries

One registry feeds every way to control CatWM from outside the app. Key binds, the `catwm` CLI and the language libraries all run the same commands.

## Parts (`Sources/CatWMKit/Control/`)

- `Command.swift`: `Command` (name, group, summary, typed arguments, result shape, access, `run`). It also holds the argument check.
- `CommandRegistry.swift`, `Commands+dispatchers.swift`, `Commands+state.swift`: the list of commands. `Commands+dispatchers.swift` makes one dispatcher entry from each `WindowAction`. A dispatcher entry calls `WindowManager.dispatch`. A query entry builds JSON from the window manager.
- `ControlServer.swift`: the Unix socket (`catwm.sock` in `Instance.configFolder`, mode `0600`, `CATWM_SOCKET` overrides it). It reads on a background queue and runs each command on the main queue, in order. It refuses a path that is longer than `sun_path` (104 bytes). It does not cut the path.
- `ControlConnection.swift`: one client. It frames lines, writes without blocking, and drops a client that falls 1 MB behind.
- `EventBus.swift`: the event list and the subscriptions. `WindowManager.notifyChange()` replaced the old `onChange?()` calls. When someone subscribes, it compares a state snapshot with the last one and emits the difference. With no subscriber it does nothing.
- `ControlCLI.swift` (in the app, `Sources/CatWM/App/`): the `catwm` command line. It reads the registry to parse arguments and print help. `main.swift` calls it for any first argument that does not start with `-`.
- `ControlSchema.swift`: writes `Clients/schema.json` from the registry.

## Instances

`CATWM_INSTANCE=<id>` starts a separate CatWM instance. The id is 1 to 24 characters of `a-z`, `0-9` and `-`. CatWM stops with exit code 2 on a bad id. It does not use the default instance, because the default instance quits the user's CatWM. `Sources/CatWMKit/App/Instance.swift` holds each path of an instance. Use `Instance` for a new file, folder or `UserDefaults` value. `Tools/check-style.sh` rejects `UserDefaults.standard`.

| | Default instance | Named instance `<id>` |
|---|---|---|
| Config folder (config, configs, templates, socket, pid file) | `~/.config/catwm/` | `~/.config/catwm/instances/<id>/` |
| Log | `~/Library/Logs/CatWM.log` | `~/Library/Logs/CatWM-<id>.log` |
| Support and cache folders | `~/Library/Application Support/CatWM/`, `~/Library/Caches/catwm/` | the same folders with `instances/<id>/` |
| Defaults | the app domain `local.catwm` | the suite `local.catwm.instance.<id>` |

Each instance writes its pid to `catwm.pid` in its config folder. At start, `AppDelegate.closePreviousInstances` stops the pid in that file if it is a CatWM. The default instance also stops each other process with the bundle ID `local.catwm`, but not a pid in `instances/*/catwm.pid`. `build.sh` does the same.

A named instance does not register a login item, link the `catwm` command, start the updater, send crash or performance reports, show onboarding, tips or What's New, or run migrations. The bundle ID and the signature do not change, so the macOS permissions of the app apply to each instance.

The CLI and the libraries read `CATWM_INSTANCE` too. `CATWM_SOCKET` wins over it.

An embedded engine (`docs/internals/embedding.md`) uses the folders of a named instance with its engine name. It listens on the socket only with `features.services.socket`, and it ignores `CATWM_SOCKET`.

## Window scope

`CATWM_SCOPE=pids:<pid>,<pid>...[;display:<display UUID>]` gives an instance a window scope. It needs `CATWM_INSTANCE`. `Instance.scope` reads the value one time. CatWM stops with exit code 2 on a bad value, also on an empty value, and on a scope without `CATWM_INSTANCE`. A bad value never means "all windows". A named instance with no scope manages every window, so it stops with exit code 2 unless you pass `--unscoped`.

A scoped instance:

- manages only the windows of these pids. `WindowScanner` removes the other windows and apps from what it reads, before the manager sees them. `observe(pid:)` and the app list of a template save also skip the other pids.
- tiles only on the display with that UUID (`Screen.all()`), if the value has `display:`.
- cannot open a template (`TemplateError.scoped`).
- does not use macOS Desktops (`virtual-workspaces` is off). It does not make, remove or show a Desktop.
- turns off focus follows mouse, mouse follows focus, quick actions and the dimming and blur panels (`WindowScope.restrict`).
- does not start the key event tap, the Caps Lock change (`hidutil`), the Desktop swipe tap or the Dock window pull tap (`GlobalInput`). `CATWM_KEYS=on` starts the key event tap again. Then the instance reads all key presses, the same as the user's CatWM. Caps Lock stays off.
- does not move the pointer, post mouse events or take key focus with its own focus window (`GlobalInput.pointerAndFocus`). `WindowManager.warpPointer`, `postMouse`, `parkFocus` and `CursorRefresh` do nothing. For example, `movefocus` toward a display with no window of the scope does nothing.
- refuses the commands in `WindowScope.refusedCommands`. `CommandRegistry.execute` stops them before they run, for each socket command, and for the dispatcher name of `dispatch`. `WindowManager.dispatch` stops the dispatchers of a key bind. The socket gives the error `failed`. These commands can change windows, Desktops or input outside the scope:
  - `nativefullscreen` reads the focused window of any app and makes a macOS Desktop.
  - `focusmonitor` moves the pointer when the display has no window.
  - `workspace`, `movetoworkspace`, `movetoworkspacesilent` and `sethomespace` change macOS Desktops. Without CatWM workspaces they send the Desktop shortcut or move the pointer.
  - `sort` and `sort-undo` move windows between macOS Desktops.
  - `switcher` shows and focuses the windows of all apps.
  - `exec` and `launch` run commands and open other apps.
  - `toggledim` and `toggleblur` put panels over the windows of all apps.
  - `grabtest` moves the pointer and posts mouse events.
  - `modefx`, `panelfx`, `intro` and `introlab` show panels over the windows of all apps.
  - `submap` starts the mode effect panels on all displays and sets the pointer image of all apps (`ModeFX`, `ModeCursor`). Without `CATWM_KEYS=on` the key event tap is off, so a key mode has no use.

`WindowScope.restrict` also removes each key bind of a refused dispatcher. A `submap` key bind does not go through `WindowManager.dispatch`, and with `CATWM_KEYS=on` it can start a key mode.

A focus command can still make the app of the target window active. The other windows of that app can then come to the front.

A scoped instance writes a claim to `scope` in its config folder: its own pid on the first line and its scope on the second line. It removes the file when it quits. An instance without a scope reads `~/.config/catwm/instances/*/scope` (`ScopeClaims`) on the background queue of `WindowScanner`, and leaves out the claimed pids. It reads the claim files again only when the modification time of the `instances` folder changes. A change in `instances/<id>/` does not change that time. So `InstancePaths.writeClaim` writes the file in `instances` first and then moves it into place with `rename`, and `removeClaim` moves it back to `instances` before it deletes it. It ignores a claim when the owner pid does not run (`kill(pid, 0)`), on each read. A scan reads the claims, but no scan starts when a claim changes. So `ScopeClaims.watch` starts a scan when the claimed pids change. It watches the `instances` folder with a vnode `DispatchSource`, and the pid of each claim owner with a process exit `DispatchSource`. Thus a claim that is written, removed or left by an owner that stopped (also with `kill -9`) starts a scan at once. A change in the folder that does not change the claimed pids starts no scan. With no claim, it watches no pid. When a pid becomes claimed, the instance without a scope forgets the windows of that pid, stops its AX observer and cancels its queued frame writes (`releaseClaimedApps`). It cannot stop an AX write that has started. So one frame write can still occur on a claimed window during the release, one time. It does not leave out the claimed display. So the user's CatWM can still tile its own windows on that display.

Add a new switch for a scoped instance to `WindowScope.restrict` (a config option), to `GlobalInput` (an event tap, a system setting, the pointer or the key focus) or to `WindowScope.refusedCommands` (a command or a dispatcher). Do not add a check at the call site. Put each new command and dispatcher in `WindowScope.allowedCommands` or in `WindowScope.refusedCommands`. A test fails if a command is in no list.

## Add a command

A dispatcher (a command that a key bind can run) is one `WindowAction` in `Sources/CatWMKit/Actions/`. The value holds the name, the CLI group and summary, the arguments, the access, the aliases, the bind picker rows and the handler. `WindowActions.all` is the only list. The registry, `WindowManager.dispatch` and the bind picker read it.

1. Add a `static let` `WindowAction` to the file of its group in `Actions/`. Give each argument a type. Use `.choice` when the values are a fixed set. Use `WindowAction.direction`, `.step` or `.text` for the usual argument shapes.
2. Add its name to `WindowActions.all`. The order of that list is the order of the CLI help and the schema.
3. Add `pickers` to show it in the bind picker. A picker row shows in its category. `order` moves a row inside its category.
4. In other code, use `WindowActions.<name>.name`, not a string. `WindowActionTests` fails if two actions use the same name or alias.
5. Run `./build.sh --dev`. It writes `Clients/schema.json` and the clients. `theSchemaFileMatchesTheRegistry` fails until the schema is current.

A command that is not a dispatcher (a query or a config command) is a `Command` in `Commands+state.swift` or `CommandRegistry.swift`.

Socket tests use dependency injection: pass a FakeBackend manager to `ControlServer(manager:)`. The server passes it through `Invocation.manager` to the command handlers; the app uses `WindowManager.shared` by default. The `workspaces` query includes catalog entries even when they have no windows and no display shows them.

## Access

- `public`: in the CLI, the schema and the libraries.
- `dev`: works over the socket, but is not in the schema (`grabtest`, `modefx`, `panelfx`, `poststyle`, `intro`, `introlab`).
- `keybindOnly`: refused over the socket (`exec`, `launch`). Any process of the user can connect, so a command that runs code must not be public.

## Add an event

Add an `EventSpec` to `EventBus.specs`. Add the field to `StateSnapshot` and the compare to `EventBus.changes`, or call `EventBus.shared.emit` at the point of the change, as `reload()` does. Then run `./build.sh --dev`.

## Libraries

`Tools/generate-clients.py` writes `Clients/python`, `Clients/typescript` and `Clients/swift` from `Clients/schema.json`. Do not edit the generated files. `Clients/python/catwm/testing.py` is written by hand: wait helpers and an event watcher for tests. Its tests run against a fake server: `python3 -I -m unittest discover Clients/python/tests`. `build.sh` copies `Clients/python/catwm` into `AgentDocs/python`. To add a language, add a writer to the script. The protocol is in `Resources/AgentDocs/cli.md`.
