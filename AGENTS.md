Building the project

```text
./build.sh 
```

For fast rebuilds while you work, use `./build.sh --dev` (debug build, a few seconds per rebuild). Do not ship a `--dev` build.

# Verifying

### Requires visual verification

build the project
output `open build/ouch.app`
state verifying needs

# Code map

The app source is in `Sources/ouch/`. Each folder has one job:

- `App/`: log, login item, permissions, updates and the performance monitor.
- `Config/`: the config model, the config file parser, the option table (`Options.swift`) and saved configs.
- `Feedback/`: the Send Feedback sheet and the upload to the report relay.
- `Keys/`: global key binds, modes, the Shortcut Map and the keyboard help overlay.
- `MenuBar/`: the menu bar item and its menu.
- `Onboarding/`: the intro, the welcome card, the keyboard tour, tips and the permission guide.
- `Overlays/`: the HUD, the mode effect and the quick-action menu at the pointer.
- `Settings/`: the Settings window and its panes.
- `Sort/`: the Sort Windows panel and its model.
- `Tiling/`: the window manager, the layouts, workspaces and the Accessibility wrappers.
- `UI/`: the design system: tokens (`Theme.swift`), controls (`Components.swift`), menus and tooltips (`Popups.swift`).
- `main.swift`: the entry point and the app delegate.

# UI rules

- Use the tokens in `UI/Theme.swift` for colour, type, symbol size, radius, spacing, shadow and motion. Do not type a raw value when a token exists.
- Use the components in `UI/Components.swift` and `UI/Popups.swift`. Do not make a local copy of a control. If a control cannot do what you need, extend it.
- For a new window or panel, use `OuchPanel` (`UI/OuchPanel.swift`).
- Run `Tools/check-style.sh` before you commit. It must pass. For a value that is a deliberate one-off (a hardware colour, the intro timing), add `// style-ok: <reason>` to the line.

# Add a setting

1. Add a property to `Config`, then add one entry for it in `Config/Options.swift`.
2. Add its row to the pane with the rows in `Settings/OptionRows.swift` (`OptionSwitch`, `OptionSlider` or `OptionRow`). The row gets its label, help, range and search anchor from the entry.
3. Add a line for it in `Resources/AgentDocs/config.md`. A test checks this file.

# Tests

Run the tests with `swift test`. If you have only the Command Line Tools (no Xcode), give the path to the testing plugin:

```text
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```
