# Ouch

Ouch is a Feature rich but simple mac os Tiling Manager.

## What makes ouch special?

These are the things we cant comprimise on, they make us what we are today and tommorow.

- Simple by default: the core works with no setup, and each advanced feature stays out of the way until the user needs it.
- Fast and smooth: performance is a core feature, and most apps ignore it. Ouch moves every window, so a slow frame or a hang is a bug. Measure it, and do not trade it for convenience.

## How it works

An event tap (`Hotkeys`) matches each key press against the binds of the active submap and sends the match to `WindowManager.dispatch` (`Tiling/Manager/`). The CLI calls the same `dispatch`. `WindowManager.shared` owns all state: one `Window` for each `CGWindowID`, and a `WorkspaceModel` for workspaces, order and layouts. `AXObserver` notifications and `WindowScanner` (`Tiling/Scan/`) feed `refresh()`. `refresh()` adds and forgets windows, asks `Layout.frames` for the slots, and places the windows. `Animator` (`Tiling/Motion/`) steps the frames at 120 Hz through one `AXWriter` queue for each app. Each workspace is one macOS Desktop. `NativeDesktopController` (`Tiling/Spaces/`) moves the Desktops with the Ouch animation settings. `Config.parse` reads `~/.config/ouch/ouch.conf` into binds and `ConfigOption` values. `reload()` applies them, and Settings edits the same file through `ConfigDocument`. The `WindowSession` module saves and opens app windows: it reads windows through AX, reads browser tabs and folders through app adapters, matches windows to saved windows and opens apps, files and URLs. `Templates/` imports it and adds the Ouch state: workspaces, Desktops, layouts and frames. Read `docs/internals/window-session.md` before you change how windows are saved or opened, or the `launch` dispatcher.

## Code map

The app source is in `Sources/ouch/`. The `WindowSession` library is in `Sources/WindowSession/`. Each folder has one job:

- `App/`: app log, login item, permissions, updates and performance monitor.
- `Config/`: the config value, the option table, the open config and saved configs.
- `Feedback/`: the Send Feedback sheet.
- `Keys/`: the event tap, the Shortcut Map, keycaps and the keyboard help overlay.
- `MenuBar/`: the menu bar icon, status menu and tip.
- `Onboarding/`: the intro, welcome card, tour, permission step and practice.
- `Overlays/`: the HUD, the mode effect and the quick-action menu.
- `Settings/`: the settings window, its pages and search.
- `Sort/`: the Overview plan, session and panel.
- `Switcher/`: the window switcher, its search and its panel.
- `Templates/`: saved workspace templates, their library and screenshot, and the Ouch part of their capture and restore (Desktops, layouts, frame placement).
- `Tiling/`: the window manager, layouts, focus dimming, animation, desktops and drag input.
- `UI/`: theme tokens, controls, menus, panels and the Design Gallery.
- `main.swift`: the entry point.

`Sources/WindowSession/` has no Ouch types. Make a type `public` only when the app uses it:

- `AX/`: AX reads that tell a timeout from a missing value, and the window ID of an AX element.
- `Model/`: `SavedWindow`, `AppState` (tabs and folders) and `LaunchSpec` (URL, arguments, command).
- `Capture/`: the AX window read for a save, and `CaptureSlot`, which runs one capture at a time with a timeout.
- `Apps/`: one `AppAdapter` for each scriptable app (Safari, Chromium browsers, Terminal, iTerm2, Finder), the `osascript` runner and the Automation check. Add an app here, not in `Templates/`.
- `Restore/`: window matching, the open scheduler and the AX reads and the "New Window" menu press used during an open.
- `Launch/`: `Launcher` (opens an app, file, URL or command) and `LaunchRequest` (the `launch` dispatcher arguments).

## Vocabulary

- **cursor** means the macOS cursor.
- **workspace** means an Ouch workspace, not a macOS Desktop.
- **window mode** means a mode where single keys control windows. A global shortcut enters it, and keys with no bind are ignored. In the config it is the `window` submap.
- **overview** means the Sort menu. Sort is the old name, and the code folder and types still use it.
- **fullscreen** means Ouch fullscreen: one window fills the screen, and Ouch still manages it.
- **maximised** means macOS native full screen: the window gets a Desktop of its own and leaves the tiling.
- **bind** means a key combination that runs a dispatcher. It is a `bind = …` line in the config.
- **dispatcher** means a named command, such as `movefocus` or `workspace`. `WindowManager.dispatch` runs it.
- **switcher** means the window switcher. `$mod Tab` opens it, and the `switcher` dispatcher runs it.
- **Desktop** means a macOS Space. Each normal Desktop is one Ouch workspace.

## UI

- Read `docs/design/design-system.md` before you build or change UI.
- Use `Theme` tokens (`UI/Theme/`) and the shared components (`UI/Components/`, `UI/Menus/`). Do not type a raw value or copy a control. If a control cannot do what you need, extend it.
- Use `OuchPanel` for a new window or panel.
- `Tools/check-style.sh` must pass. A deliberate one-off ends with `// style-ok: <reason>` on that line.

## Pull requests

- Never make a PR unless the developer explicitly asks you to do so.
- Write commit messages in English: `type(scope): description`. The scope is optional.
- Upload PR evidence to GitHub. Never commit PR-only screenshots or assets such as .github/pr-assets/.
- Write the body in this order: the problem in 1-3 sentences, a `## Changes` heading with an unordered list, and a `## Verification` heading that says how you verified the fix.
- If it is a ui change attach a pre and post image, for motion a video. If you have no pre image, attach only the post image.
- Never merge a pull request. Watch it until the developer merges it. Resolve conflicts and fix failing checks and review issues. Verify each reported bug or review issue before you fix it. Fix only a bug that you verified, and do not change code that is not part of it.

## How to work

- Do only what the developer asks. Do not add settings, UI or redesigns that they did not ask for.
- If a short request has two possible meanings, ask one question before you start.
- Before you fix a flicker, delay or animation bug, find the cause with a log, a timing or a recording. Change one thing at a time. If two tries fail, stop and report what you found.
- Do not say a bug is fixed until a test, log or recording shows it.

## Documentation

Agents read code and understand it well, comments aren't needed for everything.

## Plans, artifacts and other residue files

Do not commit implementation plans, research notes, or agent scratch files. Keep temporary working material outside the worktree.

## Dev

- Build: `./build.sh`. It installs the git hook, runs the style check, builds and makes `build/ouch.app`. Use `./build.sh --dev` for fast debug rebuilds while you work.
- Lint: `Tools/check-style.sh` must pass. The pre-commit hook, `swift test`, `./build.sh` and the `lint` GitHub Actions workflow run it. `Tools/swiftlint.sh` must pass too. The pre-commit hook and `./build.sh` run it.
- Test: `swift test`. It runs `ouchTests` and `WindowSessionTests`. Put a test for a module type in `Tests/WindowSessionTests/`. If you have only the Command Line Tools (no Xcode), add the path to the testing plugin:

```text
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

- Run and verify: you can run the app and check it with the CLI, the log and a screen recording. Do not take focus from the developer, move their windows, or test while another thread uses the Desktop. If you cannot verify a change, end your reply with "Not verified" and list each thing the developer must test.
- Config docs: after you change an option, run `swift run ouch --write-config-docs`. Read `docs/internals/add-a-setting.md` before you add or change a setting.
- Log: Ouch writes `~/Library/Logs/ouch.log`. `build/ouch.app/Contents/MacOS/ouch dump` writes the tiling state to it.

## Aditional

- Follow yagni, kiss, and SOLID.
