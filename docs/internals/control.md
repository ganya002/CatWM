# Control: the CLI, the socket and the libraries

One registry feeds every way to control CatWM from outside the app. Key binds, the `catwm` CLI and the language libraries all run the same commands.

## Parts (`Sources/CatWM/Control/`)

- `Command.swift`: `Command` (name, group, summary, typed arguments, result shape, access, `run`). It also holds the argument check.
- `CommandRegistry.swift`, `Commands+dispatchers.swift`, `Commands+state.swift`: the list of commands. A dispatcher entry calls `WindowManager.dispatch`. A query entry builds JSON from the window manager.
- `ControlServer.swift`: the Unix socket (`~/.config/catwm/catwm.sock`, mode `0600`, `CATWM_SOCKET` overrides it). It reads on a background queue and runs each command on the main queue, in order.
- `ControlConnection.swift`: one client. It frames lines, writes without blocking, and drops a client that falls 1 MB behind.
- `EventBus.swift`: the event list and the subscriptions. `WindowManager.notifyChange()` replaced the old `onChange?()` calls. When someone subscribes, it compares a state snapshot with the last one and emits the difference. With no subscriber it does nothing.
- `ControlCLI.swift`: the `catwm` command line. It reads the registry to parse arguments and print help. `main.swift` calls it for any first argument that does not start with `-`.
- `ControlSchema.swift`: writes `Clients/schema.json` from the registry.

## Add a command

1. Add a `Command` to the right list in `Control/`. Give each argument a type. Use `.choice` when the values are a fixed set.
2. Add the `case` to the `dispatch` switch when it is a dispatcher. The catalog test fails if a dispatcher has no registry entry.
3. Run `./build.sh --dev`. It writes `Clients/schema.json` and the clients. `theSchemaFileMatchesTheRegistry` fails until the schema is current.

## Access

- `public`: in the CLI, the schema and the libraries.
- `dev`: works over the socket, but is not in the schema (`grabtest`, `modefx`, `panelfx`, `poststyle`, `intro`, `introlab`).
- `keybindOnly`: refused over the socket (`exec`, `launch`). Any process of the user can connect, so a command that runs code must not be public.

## Add an event

Add an `EventSpec` to `EventBus.specs`. Add the field to `StateSnapshot` and the compare to `EventBus.changes`, or call `EventBus.shared.emit` at the point of the change, as `reload()` does. Then run `./build.sh --dev`.

## Libraries

`Tools/generate-clients.py` writes `Clients/python`, `Clients/typescript` and `Clients/swift` from `Clients/schema.json`. Do not edit the generated files. `Clients/python/catwm/testing.py` is written by hand: wait helpers and an event watcher for tests. Its tests run against a fake server: `python3 -I -m unittest discover Clients/python/tests`. `build.sh` copies `Clients/python/catwm` into `AgentDocs/python`. To add a language, add a writer to the script. The protocol is in `Resources/AgentDocs/cli.md`.
