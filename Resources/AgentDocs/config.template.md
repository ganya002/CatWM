# Config: `~/.config/catwm/catwm.config.ts`

The config is a TypeScript file that sets options on one object, `catwm`. CatWM writes `catwm.d.ts` and `tsconfig.json` next to it, so an editor completes and checks every option, key and action.

```ts
import { catwm } from "./catwm"

const mod = "alt"

catwm.mod = mod
catwm.layouts = ["tall", "bsp", "fullscreen"]
catwm.gaps.size = 10
catwm.padding = 10
catwm.motion = { style: "snappy", bounce: 0.6 }
catwm.floating.apps.push("com.apple.systempreferences", "com.apple.calculator")
for (const key of ["1", "2", "3"]) catwm.bind([mod], key, ["workspace", key])
catwm.bind([mod], "return", ["exec", "open -na Terminal"])

catwm.windows({ app: "com.apple.calculator" }, (win) => {
  win.float()
  win.position = "center"
})
catwm.workspaces({ windows: 1 }, () => {
  catwm.gaps.size = 0
})
```

- **Save to apply.** CatWM watches the config folder and the folders of imported files. A save runs the whole config again, then applies only the fields that changed. `catwm reload` does the same without a save.
- **A broken save keeps the last good config.** The error goes to the log (`config: kept the last good config, …`), to the menu bar menu and to the `errors` of the `config.reloaded` event: `{ file, line, phase, message }`. The next good save clears it.
- **Set options while the config loads.** `catwm` holds every default. An object assignment merges into it (`catwm.gaps = { size: 4 }` keeps the other gap fields). A list or a number replaces it. `undefined` goes back to the default. A list has `push(...)` and `remove(value)`, and reading an option gives its current value. A write from a promise or a timer, or after the load, is an error. There are no timers, events or native APIs. Use only erasable TypeScript syntax (no `enum` or `namespace`); the shipped `tsconfig.json` sets `erasableSyntaxOnly`.
- **`export default` is gone.** A file that default-exports a config gets an error that shows how to convert it. Old names get an error too: `animation` is `motion`, `panelAnimation` is `motion.panels`, `modeEffect` is `motion.modeEffect`.
- **Motion styles.** `catwm.motion.style = "snappy"` sets `enabled`, `curve` and `duration` to the style's values, and a later write to one field overrides that field. Reading `style` gives the style whose values all match, or `undefined`. The styles are the tiles in Settings → Motion.
- **Window rules.** `catwm.windows(match, win => …)` runs once while the config loads and records what it does: `win.float()`, `win.tile()`, `win.fullscreen()`, `win.size = { width, height }`, `win.position = "center"` or `{ x, y }`, `win.workspace = "3"` and `win.display = "external"`. `match` takes `app` (wildcards work), `title` (a string or a RegExp), `pid`, `role`, `workspace`, `display`, `floating`, `minimized` and `fullscreen`. A RegExp must be one that macOS can match, or the rule is an error. CatWM checks the rules when a window appears and when its title changes, and a rule applies once each time a window starts matching, so it doesn't pull a window back after you move it. If two rules match at once, the later one in the file wins. **Floating: the latest change wins.** `floating.apps`, a rule's `win.float()` or `win.tile()`, and the `togglefloating` key don't rank above each other. Whichever happened last decides. A save that doesn't change a window's result leaves your toggle alone.
- **Workspace rules.** `catwm.workspaces(match, () => …)` records option writes for the workspaces that match. `match` takes `windows` and `sameApp` (a number or `{ atLeast, atMost }`), `app`, `layout`, `name`, `display` and `focused`. A rule can set only the options marked scoped in `catwm.d.ts`: gaps, padding, layouts, `newWindowsToMain`, the motion fields and the focus dimming. Another option, or `catwm.bind`, is an error. CatWM checks them on each refresh, before it lays the workspace out, and the last matching rule wins for each field. A rule beats a Settings override.
- **Imports:** relative paths only, such as `import { gap } from "./gaps"`. `"./catwm"` is the host module, not a file.
- **Settings and `catwm config.set`** never edit the TypeScript file. They write `catwm.overrides.json` beside it. The order is defaults, then `catwm.config.ts`, then the overrides. Settings → General lists each override and can drop it, so the file value applies again.
- **Features:** `catwm.features.presentation.hud = true` turns parts of CatWM on or off. Embedded mode will read these switches. Standalone CatWM checks them but keeps every feature on for now.
- **From `catwm.conf`:** the first launch converts an existing `catwm.conf` to `catwm.config.ts` once, checks that the result gives the same config, and keeps `catwm.conf` as an unread backup. If the conversion fails, CatWM keeps using `catwm.conf` and says why in the log and the menu bar menu.

## Options

Each option is a path on `catwm`: `gaps.size` is `catwm.gaps.size`. `padding` also takes one number for all four sides.

| Option | Value | Default | Notes |
|---|---|---|---|
| `mod` | `"cmd"` / `"alt"` / `"ctrl"` / `"shift"`, or a list | `"alt"` | the main modifier. `.conf`: `$mod` |
| `layouts` | list of layout names | `{{default-layouts}}` | the cycle; each layout once. Names below |
| `floating.apps` | list of bundle IDs | empty (first run: System Settings, Calculator) | apps that float (or the only ones that tile, see `floating.listedAppsFloat`). Wildcards such as `com.adobe.*` work. A window rule or a toggle can still override one window. `.conf`: `floating` |
{{options}}
| `catwm.bind(mods, key, run, options?)` | a call, not an option | | see [keybinds.md](keybinds.md) |
| `features.<group>.<feature>` | bool | `true` | see `catwm.d.ts` for the list |

## Layout names

{{layouts}}.

## Settings window and saved configs

Menu bar → **Settings…** (⌘,). Panes: General, Layout, Windows, Motion, Templates, Shortcuts. Changes save to `catwm.overrides.json` and apply at once. **Configs** (menu bar submenu / Settings) stores named keyboard, animation, and full presets in `~/.config/catwm/configs.json`; switching one writes its values as overrides. Presets can be imported and exported.

Hand edits to `catwm.config.ts` apply on save. A value that Settings changed stays overridden until you drop it in Settings → General.

## Workspace templates

Settings → **Templates** lists saved workspaces with large screenshot previews. Click a screenshot to enlarge it. Open, rename, update, or delete a template here. A template stores app identities, document addresses when available, window frames, display sizes, layouts, main-pane ratios and counts, window order, tiling status, and floating, minimized, zoomed, or native full screen states. Templates are stored in `~/.config/catwm/templates.json`, separately from configs. Screenshots are stored in that file. Screen recording access is required to capture them. Saving still works without that access. Update an older template to add a screenshot.

With `template-app-scripting = true` (Settings → Templates → **Save tabs and folders**), a template also saves:

- the tabs of Safari and Chromium browser windows (Chrome, Brave, Edge, Vivaldi, Helium), but not private or incognito windows
- the folders of Terminal and iTerm2 tabs
- the folders of each Finder window and its tabs
- the project of VS Code, Cursor, VSCodium, Windsurf, Zed and Xcode windows

macOS asks once for each scripted app to let CatWM control it. The code editors need no permission: CatWM reads their recent-project files. A background tab of a Terminal or Finder window is saved as a tab of its window, not as a separate window.

Opening the template reopens the browser tabs, the iTerm2 tabs and all Terminal tabs (through a temporary Terminal window group). It opens each Finder window at its selected folder, and each editor at its project, so that the editor brings back its own files and panes. If an app does not allow control, CatWM opens the window as before.

Each saved window in `templates.json` can have an optional `launch` object that you edit by hand: `"url"` opens a URL or deep link with the app (for example `vscode://file/…` or `slack://channel?…`), `"arguments"` passes launch arguments when CatWM starts the app, and `"command"` runs a shell command with `sh -c` instead of opening a new window. `command` is used first, then saved tabs, then `url`, then the saved document.

In window mode, tap the mode modifier to open quick actions at the pointer. Press **S** to show a name field beside Save. Type the name and press Return to save without opening Settings. The screenshot can finish after the template saves. Escape cancels naming and returns to the action list. Press **1–9** to open a saved template. Hover a template to replace its number with an X. Click the X to delete it without closing the menu. Arrow keys and Return select an action. These actions also work over empty desktop space.

Quick actions also retain the focus controls: **D** toggles Dim other windows, and **B** toggles Blur other windows.

Restore reuses matching windows in the current workspace, opens missing apps or supplied documents, and requests new windows from apps that support them. Missing displays use available displays. Frames scale to fit. Existing extra windows stay open. Tabs, unsaved work, and other internal app state are not saved. CatWM reports windows that it cannot open or position.
