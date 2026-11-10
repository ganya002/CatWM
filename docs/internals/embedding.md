# Embedded mode: CatWMKit in a host app

`CatWMKit` is the engine as a static SwiftPM library product. The CatWM app links it, and so can another Mac app (the host). A host creates one `CatWMEngine`, gives it a TypeScript config and drives it from Swift. The engine runs in the host's process, so the host owns the GUI, the permissions and the process. `Examples/EmbedHost/` is a minimal host.

## Link it

Add the CatWM package as a source dependency and depend on the `CatWMKit` product:

```swift
.package(name: "CatWM", path: "../CatWM"),
.executableTarget(name: "Host", dependencies: [.product(name: "CatWMKit", package: "CatWM")])
```

The host must not be sandboxed. A sandboxed app can't use the Accessibility API. The host needs Accessibility for tiling, and `NSAppleEventsUsageDescription` in its `Info.plist` for the session adapters.

## The engine (`Sources/CatWMKit/Embed/`)

```swift
let engine = try CatWMEngine()                      // or CatWMEngine(name: "my-host")
try engine.start(config: .text(source))             // or .file(url), with HMR
try engine.start(config: .text(source), scope: .init(pids: [pid]))
for await event in engine.events() { ... }          // the socket events, plus permissions.changed
try engine.setOption("gaps.size", to: 12)           // an override until resetOption
try engine.perform("layout", ["layout": "wide"])    // a command from Clients/schema.json
let state = engine.snapshot()                       // features, permissions, diagnostics, windows
await engine.stop()
```

- `CatWMEngine.swift`: the public API. It runs every call on the command registry and the event bus, with no socket and no JSON text. `perform` keeps the access checks: a `keybindOnly` command fails with `forbidden`.
- `CatWMEngine+types.swift`: the public values. `Option` describes each TypeScript option and each `features` leaf: the ID (its path in the config), kind, choices, range, default, current value and the feature it needs. The public `JSON` value comes from `Control/JSON.swift`.
- `EngineSurface.swift`: the `TilingSurface` of embedded mode. It draws nothing. It sends key binds to the window manager and runs the notification sources.

The engine name sets the storage. The default is `embed-` and the host's bundle ID, cut to 24 characters. The engine uses the named-instance folders of that name (`docs/internals/control.md`), so it never reads or writes the files of the user's own CatWM, and it ignores `CATWM_INSTANCE`, `CATWM_SCOPE`, `CATWM_KEYS` and `CATWM_SOCKET`.

## Features

In embedded mode every `features` leaf is off until the config turns it on. `Config.embedded` is the starting value, and `ConfigStore(embedded: true)` reads the TypeScript value over it. `presentation` and `input.cursorActions` draw GUI, so embedded mode doesn't have them: a config that turns one on fails with a diagnostic. `Feature.needs` lists the dependencies, and most leaves need `windows.tiling`.

A leaf that is off starts nothing:

| Leaf | What it starts |
|---|---|
| `windows.tiling` | `WindowManager.startTiling`: the `NSWorkspace` observers, the `NSEvent` monitors, the AX observers, the scans and the layout |
| `windows.desktops` | `virtual-workspaces`, so each workspace is a macOS Desktop |
| `windows.tabGroups` | the `tabs` dispatchers, tab drops and the saved groups. Turning it off splits every group |
| `services.templates` | template capture and restore |
| `input.keys` | the key event tap (`Hotkeys`) |
| `input.mouse`, `input.gestures` | the Dock pull tap and the swipe tap |
| `services.notifications` | the unread badge sources |
| `services.socket` | `ControlServer` on `catwm.sock` in the engine's folder. Embedded mode installs no CLI |

`WindowManager.effective` turns the options of an off leaf off, so `apply` stops a subsystem that a config change turns off. The standalone app keeps every leaf on by default and reads the `presentation` leaves in `AppSurface`.

## Start and stop

One engine runs in a process. A second `start` throws `alreadyRunning`. `start` throws `config` with the diagnostics when the first config fails, and starts nothing. A later broken change keeps the last good config, throws from `replaceConfig` or `loadConfig`, and shows in `snapshot().diagnostics` and the `config.reloaded` event.

Each `start` installs a new `WindowManager` as `WindowManager.shared`. `stop` calls `WindowManager.stopTiling` and `stopServices`: they remove the event taps, the `NSEvent` monitors, the `NSWorkspace` and AX observers, the claim watch, the config watch and the socket, put parked windows back, and finish the event streams. A host calls `stop` before it quits.

Overrides from `setOption` stay in memory: they survive HMR and `stop`, and `resetOption` drops one. `overrides` gives them to the host to save.

## The host's process

The library never sets the activation policy or the main menu, never calls `NSApp.terminate` or installs signal handlers, never stops other instances and never runs `CommandLine.arguments[0]`. The `exit` dispatcher fails in embedded mode. The CatWM Desktop slide needs its guard process, which is a second run of the executable, so with `windows.desktops` on, embedded mode switches Desktops with the macOS swipe (`NativeDesktopController.guarded`). CatWM doesn't change Caps Lock and doesn't make its focus window.

The library never asks for a permission. `snapshot().permissions` reports Accessibility, Input Monitoring, Screen Recording and Full Disk Access, and `permissions.changed` reports a change. Tiling starts when the host gets Accessibility.

## Coexistence

With a `scope`, the engine manages only those pids, and only that display when `display` is set. It writes a scope claim (`instances/<name>/scope`) and the user's CatWM leaves the claimed pids alone. Without a scope it tiles every window, the same as the user's CatWM.
