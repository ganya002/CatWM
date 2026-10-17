# Comments

Comments are unallowed. Do not add comments.

`Package.swift` keeps its `// swift-tools-version:` line. Swift Package Manager requires that line.

Building the project

```text
./build.sh 
```

For fast rebuilds while you work, use `./build.sh --dev` (debug build, a few seconds per rebuild). Do not ship a `--dev` build.

# Verifying

### Requires visual verification

output `./build.sh --dev && open build/ouch.app`
state verifying needs

# Code map

The app source is in `Sources/ouch/`. Each folder has one job:

- `App/`: log and the login item. `Permissions/`, `Updates/` and `Perf/` hold the permission watcher, Sparkle and the performance monitor. `AppDelegate.swift` is the delegate.
- `Config/`: `Model/` is the config value and the default text, `Options/` is the option table, `Document/` is the open config, `Library/` is saved configs.
- `Feedback/`: the Send Feedback sheet and the upload to the report relay.
- `Keys/`: `Hotkeys/` is the event tap, `Map/` is the Shortcut Map, `Keyboard/` draws the keycaps, `Help/` is the keyboard help overlay. Caps Lock chords stay in `CapsLockChord.swift`.
- `MenuBar/`: the menu bar icon, `Menu/` for the status menu, `Tip/` for the menu bar tip.
- `Onboarding/`: `Session/` starts the flow, `Intro/` plays the intro, `Welcome/` is the welcome card, `Coach/` and `Lessons/` are the tour, then `Tips/`, `Permission/` and `Practice/`.
- `Overlays/`: the HUD, `Mode/` for the mode effect, `Cursor/` for the quick-action menu.
- `Settings/`: `Window/` is the window, `Chrome/` is the shell, `Panes/` are the pages, `Configs/` is saved-config UI, `Rows/` and `Search/` support them.
- `Sort/`: `Plan/` is the plan, `Model/` is the session, `Views/` is the panel content, `Panel/` is the window, `Nudge/` is the offer.
- `Tiling/`: `Manager/` is the window manager, `Access/` is Accessibility and window-server calls, `Layout/` is the layouts, `Focus/` dims unfocused windows, `Motion/` animates frames, `Spaces/` is desktops, `Scan/` finds windows, `Input/` is drag-anywhere and the Dock pull.
- `UI/`: `Theme/` is the tokens, `Components/` is the controls, `Menus/` is menus and tooltips, `Chrome/` is panels, `Gallery/` is the Design Gallery (debug builds only).
- `main.swift`: the entry point.

# UI rules

- Read `docs/design-system.md` before you build or change UI. It says how each component must look and when to use it. To see the components, open the Design Gallery: `./build.sh --dev`, then `open build/ouch.app --args --gallery`. When you add or change a component, update its example in `UI/Gallery/`.
- Use the tokens in `UI/Theme/` for colour, type, symbol size, radius, spacing, shadow and motion. Do not type a raw value when a token exists.
- Use the components in `UI/Components/` and `UI/Menus/`. Do not make a local copy of a control. If a control cannot do what you need, extend it. Each control is its own file under `Controls/`, `Rows/`, `Keys/`, or `Picker/`.
- For a new window or panel, use `OuchPanel` (`UI/Chrome/OuchPanel.swift`).
- Run `Tools/check-style.sh` before you commit. It must pass. For a value that is a deliberate one-off (a hardware colour, the intro timing), add `// style-ok: <reason>` to the line.

# Add a setting

1. Add a property to `Config`, then add one entry for it in `Config/Options/Options.swift`.
2. Add its row to the pane with the rows in `Settings/Rows/` (`OptionSwitch`, `OptionSlider` or `OptionRow`). The row gets its label, help, range and search anchor from the entry.
3. Add a line for it in `Resources/AgentDocs/config.md`. A test checks this file.

# Tests

Run the tests with `swift test`. If you have only the Command Line Tools (no Xcode), give the path to the testing plugin:

```text
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```
