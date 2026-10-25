# Control: the CLI, the socket and the libraries

One registry feeds every way to control CatWM from outside the app. Key binds, the `catwm` CLI and the language libraries all run the same commands.

## Parts (`Sources/CatWM/Control/`)

- `Command.swift`: `Command` (name, group, summary, typed arguments, result shape, access, `run`). It also holds the argument check.
- `CommandRegistry.swift`, `Commands+dispatchers.swift`, `Commands+state.swift`: the list of commands. `Commands+dispatchers.swift` makes one dispatcher entry from each `WindowAction`. A dispatcher entry calls `WindowManager.dispatch`. A query entry builds JSON from the window manager.
- `ControlServer.swift`: the Unix socket (`~/.config/catwm/catwm.sock`, mode `0600`, `CATWM_SOCKET` overrides it). It reads on a background queue and runs each command on the main queue, in order.
- `ControlConnection.swift`: one client. It frames lines, writes without blocking, and drops a client that falls 1 MB behind.
- `EventBus.swift`: the event list and the subscriptions. `WindowManager.notifyChange()` replaced the old `onChange?()` calls. When someone subscribes, it compares a state snapshot with the last one and emits the difference. With no subscriber it does nothing.
- `ControlCLI.swift`: the `catwm` command line. It reads the registry to parse arguments and print help. `main.swift` calls it for any first argument that does not start with `-`.
- `ControlSchema.swift`: writes `Clients/schema.json` from the registry.

## Add a command

A dispatcher (a command that a key bind can run) is one `WindowAction` in `Sources/CatWM/Actions/`. The value holds the name, the CLI group and summary, the arguments, the access, the aliases, the bind picker rows and the handler. `WindowActions.all` is the only list. The registry, `WindowManager.dispatch` and the bind picker read it.

1. Add a `static let` `WindowAction` to the file of its group in `Actions/`. Give each argument a type. Use `.choice` when the values are a fixed set. Use `WindowAction.direction`, `.step` or `.text` for the usual argument shapes.
2. Add its name to `WindowActions.all`. The order of that list is the order of the CLI help and the schema.
3. Add `pickers` to show it in the bind picker. A picker row shows in its category. `order` moves a row inside its category.
4. In other code, use `WindowActions.<name>.name`, not a string. `WindowActionTests` fails if two actions use the same name or alias.
5. Run `./build.sh --dev`. It writes `Clients/schema.json` and the clients. `theSchemaFileMatchesTheRegistry` fails until the schema is current.

A command that is not a dispatcher (a query or a config command) is a `Command` in `Commands+state.swift` or `CommandRegistry.swift`.

## Access

- `public`: in the CLI, the schema and the libraries.
- `dev`: works over the socket, but is not in the schema (`grabtest`, `modefx`, `panelfx`, `poststyle`, `intro`, `introlab`).
- `keybindOnly`: refused over the socket (`exec`, `launch`). Any process of the user can connect, so a command that runs code must not be public.

## Add an event

Add an `EventSpec` to `EventBus.specs`. Add the field to `StateSnapshot` and the compare to `EventBus.changes`, or call `EventBus.shared.emit` at the point of the change, as `reload()` does. Then run `./build.sh --dev`.

## Libraries

`Tools/generate-clients.py` writes `Clients/python`, `Clients/typescript` and `Clients/swift` from `Clients/schema.json`. Do not edit the generated files. `Clients/python/catwm/testing.py` is written by hand: wait helpers and an event watcher for tests. Its tests run against a fake server: `python3 -I -m unittest discover Clients/python/tests`. `build.sh` copies `Clients/python/catwm` into `AgentDocs/python`. To add a language, add a writer to the script. The protocol is in `Resources/AgentDocs/cli.md`.
