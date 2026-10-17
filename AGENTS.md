# Comments

Comments are unallowed. `Tools/check-style.sh` fails on them. The pre-commit hook, `swift test`, `./build.sh`, and the `lint` GitHub Actions workflow run that check. `./build.sh` installs the hook into this clone.

`Package.swift` keeps its `// swift-tools-version:` line. Swift Package Manager requires that line. The only other comment is `// style-ok: <reason>` at the end of a line that the check already flags. The reason is two words or more, and it covers that line only.

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

- Read `docs/design-system.md` before you build or change UI. It says how each component must look and when to use it.
- Use the tokens in `UI/Theme/` for colour, type, symbol size, radius, spacing, shadow and motion. Do not type a raw value when a token exists.
- Use the components in `UI/Components/` and `UI/Menus/`. Do not make a local copy of a control. If a control cannot do what you need, extend it. Each control is its own file under `Controls/`, `Rows/`, `Keys/`, or `Picker/`.
- For a new window or panel, use `OuchPanel` (`UI/Chrome/OuchPanel.swift`).
- `Tools/check-style.sh` must pass. It rejects hard-coded styles (use a `Theme` token) and `NSPanel` (use `OuchPanel`). A deliberate one-off (a hardware colour, the intro timing, a panel that is not `OuchPanel`) ends with `// style-ok: <reason>` on that line.

# Add a setting

1. Add a property to `Config`.
2. Add one option declaration with `.setting(...)` in `Config/Options/Options.swift`. Set its section, order, range, and enabled state there. Effect descriptors can publish their options beside the effect.
3. Run `swift run ouch --write-config-docs`. This generates `Resources/AgentDocs/config.md` from the option declarations and `config.template.md`.

`OptionRows` renders the declaration. Settings search reads the same declaration. Keep custom controls in that renderer. Put pointer behavior in `PointerActions` or its effect descriptor. The build collects custom search entries, dispatcher names, and palette tokens. The linter rejects duplicate catalogs. Catalog rules do not accept `style-ok` escapes.

# Tests

Run the tests with `swift test`. If you have only the Command Line Tools (no Xcode), give the path to the testing plugin:

```text
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```
