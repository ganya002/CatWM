# CatWM

CatWM is a Feature rich but simple mac os Tiling Manager.

## What makes CatWM special?

These are the things we cant comprimise on, they make us what we are today and tommorow.

- Simple by default: the core works with no setup, and each advanced feature stays out of the way until the user needs it.
- Intuitive: Users need to get real work done, not tinker around with a Tiling Manager. We always have to strive to feel native and obvious.
- Fast and smooth: performance is a core feature, and most apps ignore it. CatWM moves every window, so a slow frame or a hang is a bug. Measure it, and do not trade it for convenience.

## General principels

- Channel your inner yagni, kiss, and SOLID.
- Before adding complexity for a speculative or vanishingly unlikely race or security edge case, explain the concrete failure mode, likelihood, and complexity cost to the user and get their buy-in. Do not silently expand scope for theoretical robustness.
- Do not write bypasses, write real fixes.
- Keep things in one function unless composable or reusable.
- Before adding complexity for a speculative or vanishingly unlikely race or security edge case, explain the concrete failure mode, likelihood, and complexity cost to the user and get their buy-in. Do not silently expand scope for theoretical robustness.
- If a short request has two possible meanings, ask one question before you start.
- Do not say a bug is fixed until a test, log or recording shows it.

## How it works

An event tap (`Hotkeys`) matches each key press against the binds of the active submap and sends the match to `WindowManager.dispatch` (`Tiling/Manager/`), which runs the `WindowAction` of that name (`Actions/`). The CLI and the language libraries call the same command registry (`Control/`) through a Unix socket. Read `docs/internals/control.md` before you add a command or an event. `WindowManager.shared` owns all state: one `Window` for each `CGWindowID`, and a `WorkspaceModel` for workspaces, order and layouts. `Tiling/` does not call UI types. It calls `WindowManager.surface` (`TilingSurface`). `AppSurface` (`App/`) sends these calls to the HUD, tab strips, keys and panels, and tests use `HeadlessSurface`. `Tools/check-style.sh` rejects a UI singleton in `Tiling/`. `AXObserver` notifications and `WindowScanner` (`Tiling/Scan/`) feed `refresh()`. `refresh()` adds and forgets windows, asks `Layout.frames` for the slots, and places the windows. `Animator` (`Motion/Windows/`) steps the frames at 120 Hz through one `AXWriter` queue for each app. Each workspace is one macOS Desktop. `NativeDesktopController` (`Tiling/Spaces/`) moves the Desktops with the CatWM animation settings, through `DesktopMotion` (`Motion/Desktop/`). `ConfigStore` runs `~/.config/catwm/catwm.config.ts` on its own JavaScriptCore thread, adds `catwm.overrides.json` and gives one `Config`. A save re-runs only the changed modules, and `WindowManager.apply` applies only the fields that changed. Settings writes overrides through `ConfigDocument`. Read `docs/internals/config.md` before you change how the config loads or applies. `Session/` saves and opens app windows: it reads windows through AX, reads browser tabs and folders through app adapters, matches windows to saved windows and opens apps, files and URLs. `Templates/` uses it and adds the CatWM state: workspaces, Desktops, layouts and frames. Read `docs/internals/window-session.md` before you change how windows are saved or opened, or the `launch` dispatcher.

## Code map

The app source is in `Sources/CatWM/`. Each folder has one job:

- `Actions/`: one `WindowAction` for each dispatcher (CLI command, bind picker rows and handler). `WindowActions.all` is the only list.
- `App/`: app log, login item, permissions, updates, performance monitor and `AppSurface`.
- `Control/`: the command registry, the socket server, events and the CLI client.
- `Config/`: the config value, the option table, the open config and saved configs.
- `Feedback/`: the Send Feedback sheet.
- `Keys/`: the event tap, the Shortcut Map, keycaps and the keyboard help overlay.
- `MenuBar/`: the menu bar icon, status menu and tip.
- `Motion/`: all animation. Read `docs/internals/animation.md` before you animate anything. `Engine/`: the curve, `MotionSpec` and `Trajectory`. `Windows/`: `Animator` and `AXWriter`, which move window frames at 120 Hz. `Desktop/`: `DesktopMotion`, the Desktop slide. `Kit/`: the SwiftUI `Motion.*` tokens and the AppKit helpers (`Motion.group`, `Motion.fade`, `PanelGlide`).
- `Notifications/`: the unread badge of each window, its sources (Dock, Notification Center database and banners) and its listeners. Read `docs/internals/notifications.md` before you add a source.
- `Onboarding/`: the intro, welcome card, tour, permission step and practice.
- `Overlays/`: the HUD, the mode effect and the quick-action menu.
- `Session/`: the save and open of app windows. See below.
- `Settings/`: the settings window, its pages and search.
- `Sort/`: the Overview plan, session and panel.
- `Switcher/`: the window switcher, its search and its panel.
- `Templates/`: saved workspace templates, their library and screenshot, and the CatWM part of their capture and restore (Desktops, layouts, frame placement).
- `Tiling/`: the window manager, layouts, focus dimming, animation, desktops and drag input.
- `UI/`: theme tokens, controls, menus, panels and the Design Gallery.
- `main.swift`: the entry point.

`Session/` has no CatWM types, such as `WindowManager`, `WorkspaceModel`, `Layout`, `Theme` or `HUD`. `Templates/` uses it. `Tools/check-style.sh` rejects these names in `Session/`. Its folders:

- `AX/`: AX reads that tell a timeout from a missing value, and the window ID of an AX element.
- `Model/`: `SavedWindow`, `AppState` (tabs and folders) and `LaunchSpec` (URL, arguments, command).
- `Capture/`: the AX window read for a save, and `CaptureSlot`, which runs one capture at a time with a timeout.
- `Apps/`: one `AppAdapter` for each app with extra state: browsers, Terminal, iTerm2 and Finder (through scripts), and code editors (through their recent-project files). It also holds the `osascript` runner, the Automation check and `WindowTabs` (background tabs). Add an app here, not in `Templates/`.
- `Restore/`: window matching, the open scheduler and the AX reads and the "New Window" menu press used during an open.
- `Launch/`: `Launcher` (opens an app, file, URL or command) and `LaunchRequest` (the `launch` dispatcher arguments).

## Vocabulary

Read `docs/internals/vocabulary.md` for the words CatWM uses, such as workspace, Desktop, fullscreen and overview.

## UI

- Read `docs/design/design-system.md` before you build or change UI.
- Use `Theme` tokens (`UI/Theme/`) and the shared components (`UI/Components/`, `UI/Menus/`). Do not type a raw value or copy a control. If a control cannot do what you need, extend it.
- Use `CatWMPanel` for a new window or panel.
- `Tools/check-style.sh` must pass. A deliberate one-off ends with `// style-ok: <reason>` on that line.

## Animation

- Animate only through `Motion/`. A window frame uses `Animator`, a Desktop slide uses `DesktopMotion`, a panel uses `PanelGlide`, `Motion.fade` or `Motion.group`, and SwiftUI uses a `Motion.*` token.
- A new kind of animation gets a function in `Motion/`, never a raw call at the call site.
- `Tools/check-style.sh` rejects `NSAnimationContext`, `.animator()`, `CA*Animation`, display links, timers under 0.1 s and raw SwiftUI curves outside `Motion/`. `// style-ok` cannot silence these.

## Branch names

Use a short branch name of at most three words, separated by hyphens.

Examples: session-recovery, fix-scroll-state, regenerate-sdk.

## Pull requests

Never make a pr unless you've been asked to.

Write conventinal commit titles in plain english. `feat(animation): force windows to render faster`. Start the body by explaining the problem with 1-2 concise sentences. Under this add any media like screenshots (via `--attach`, never commit assets), benchmark results in a grid and or etc. Under `## changes` list what changes you've made in an ul, continue with a short section on how you verified. Omit things such as linter and style-check. Then watch the pr until it has been merged. Adress conflicts, and comments. Verify each reported bug or review issue before you fix it. Fix only a bug that you verified.

## Documentation

Agents read code and understand it well, comments aren't needed for everything.

## Plans, artifacts and other residue files

Do not commit implementation plans, research notes, or agent scratch files. Keep temporary working material outside the worktree.

## Checks

- Build: run `./build.sh --dev`. Run `./build.sh` only for a release build. A build stops the running CatWM only with `--replace`. Set `CATWM_INSTANCE=<id>` to build next to it.
- Lint: `Tools/check-style.sh` and `Tools/swiftlint.sh` must pass. The pre-commit hook and the `lint` GitHub Actions workflow run them.
- `Tools/check-style.sh` also rejects a raw AX app element (use `axApp`), `NSLog` and `print` (use `Log`), a `try?` that drops a write failure (use `Log.attempt`), and a `UserDefaults` key literal (use `DefaultsKey`). It also rejects a timer wait (`asyncAfter`, `Task.sleep`) in `Tiling/` unless the line ends with `// style-ok: <why no event exists>`, a stored `static var`, `@unchecked Sendable`, `MainActor.assumeIsolated`, a sleep in a test, a discarded run error, a discarded directory creation error, and a fixed run-loop wait in a test. Its message names the fix.
- `./build.sh` writes the schema, the clients and the config docs. Add the changed generated files to your change. Read `docs/internals/add-a-setting.md` before you add or change a setting.

## Testing

Run `swift test`. Put a test for an app type, also a `Session/` type, in `Tests/CatWMTests/`.

- Test actual implementation, do not duplicate logic into tests.
