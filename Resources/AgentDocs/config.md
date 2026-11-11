# Config: `~/.config/catwm/catwm.config.ts`

The config is plain TypeScript: one default-exported object. CatWM writes `catwm.d.ts` and `tsconfig.json` next to it, so an editor completes and checks every option, key and action.

```ts
import type { Bind, Config } from "./catwm"

const mod = "alt"

export default {
  mod,
  layouts: ["tall", "bsp", "fullscreen"],
  gaps: { size: 10 },
  padding: 10,
  animation: { curve: "spring", bounce: 0.6 },
  floating: { apps: ["com.apple.systempreferences", "com.apple.calculator"] },
  binds: [
    ...(["1", "2", "3"] as const).map((key): Bind => ({ mods: [mod], key, run: ["workspace", key] })),
    { mods: [mod], key: "return", run: ["exec", "open -na Terminal"] },
  ],
} satisfies Config
```

- **Save to apply.** CatWM watches the config folder and the folders of imported files. A save re-runs only the changed module and the modules that import it, then applies only the fields that changed. `catwm reload` runs every module again.
- **A broken save keeps the last good config.** The error goes to the log (`config: kept the last good config, …`), to the menu bar menu and to the `errors` of the `config.reloaded` event: `{ file, line, phase, message }`. The next good save clears it.
- **Data only.** Functions, loops and imports can compute the config, but the exported value must be plain data. A function in it is an error. There are no timers, events or native APIs. Use only erasable TypeScript syntax (no `enum` or `namespace`); the shipped `tsconfig.json` sets `erasableSyntaxOnly`.
- **Imports:** relative paths only, such as `import { binds } from "./binds"`. A type import from `"./catwm"` is free.
- **Settings and `catwm config.set`** never edit the TypeScript file. They write `catwm.overrides.json` beside it. The order is defaults, then `catwm.config.ts`, then the overrides. Settings → General lists each override and can drop it, so the file value applies again.
- **Features:** `features: { windows, input, services, presentation }` turns parts of CatWM on or off, such as `features: { presentation: { hud: true } }`. Embedded mode will read these switches. Standalone CatWM checks them but keeps every feature on for now.
- **From `catwm.conf`:** the first launch converts an existing `catwm.conf` to `catwm.config.ts` once, checks that the result gives the same config, and keeps `catwm.conf` as an unread backup. If the conversion fails, CatWM keeps using `catwm.conf` and says why in the log and the menu bar menu.

## Options

Each option is a path in the config object: `gaps.size` is `gaps: { size: … }`. `padding` also takes one number for all four sides.

| Option | Value | Default | Notes |
|---|---|---|---|
| `mod` | `"cmd"` / `"alt"` / `"ctrl"` / `"shift"`, or a list | `"alt"` | the main modifier. `.conf`: `$mod` |
| `layouts` | list of layout names | `bsp, wide, floating, fullscreen` | the cycle; each layout once. Names below |
| `floating.apps` | list of bundle IDs | empty (first run: System Settings, Calculator) | apps that float (or the only ones that tile, see `floating.listedAppsFloat`). Wildcards such as `com.adobe.*` work. `.conf`: `floating` |
| `floating.listedAppsFloat` | bool | `true` | true: listed apps float. false: only listed apps are tiled. `.conf`: `floating-is-blacklist` |
| `gaps.enabled` | bool | `true` | gaps between windows. `.conf`: `window-margins` |
| `gaps.size` | 0–100 points | `10` | `gaps_in` is accepted and doubled. `.conf`: `window-margin-size` |
| `gaps.smart` | bool | `true` | no gaps with a single window. `.conf`: `smart-window-margins` / `smart-gaps` |
| `padding.left` | 0–500 points | `10` | `screen-padding` or `gaps_out` sets all four sides. `.conf`: `screen-padding-left` |
| `padding.right` | 0–500 points | `10` | `.conf`: `screen-padding-right` |
| `padding.top` | 0–500 points | `10` | `.conf`: `screen-padding-top` |
| `padding.bottom` | 0–500 points | `10` | `.conf`: `screen-padding-bottom` |
| `noPaddingOnBuiltinDisplay` | bool | `true` | `.conf`: `disable-padding-on-builtin-display` |
| `ignoreMenuBar` | bool | `false` | tile over the menu bar area. `.conf`: `ignore-menu-bar` |
| `focus.mouseFollowsFocus` | bool | `true` | `.conf`: `mouse-follows-focus` |
| `focus.followsMouse` | bool | `true` | `.conf`: `focus-follows-mouse` / `follow_mouse` |
| `focus.followsMouseInModeOnly` | bool | `true` | with `focus-follows-mouse` on, hovering focuses a window only while window mode is on. `.conf`: `focus-follows-mouse-in-mode-only` |
| `mouse.swapsWindows` | bool | `true` | drag a tile onto another to swap. `.conf`: `mouse-swaps-windows` |
| `mouse.resizesWindows` | bool | `true` | drag edges to resize. `.conf`: `mouse-resizes-windows` |
| `mouse.splitHandle` | bool | `true` | a bar on the main split: drag it to resize, click it to swap the sides. `.conf`: `split-handle` |
| `tabs.autoHideStrip` | bool | `false` | hide each tab strip until the pointer reaches the top of its window. `.conf`: `auto-hide-tab-strip` |
| `tabs.notificationBadges` | bool | `true` | show a red badge with the unread count on each tab. `.conf`: `tab-notification-badges` |
| `newWindowsToMain` | bool | `false` | `.conf`: `new-windows-to-main` / `new_is_master` |
| `floating.smallWindows` | bool | `true` | `.conf`: `float-small-windows` |
| `resizeStep` | number | `5` | percent (`5`) or fraction (`0.05`); 1 or more is read as percent. `.conf`: `window-resize-step` |
| `layoutHud.enabled` | bool | `false` | HUD when the layout changes. `.conf`: `enables-layout-hud` |
| `layoutHud.onSpaceChange` | bool | `true` | `.conf`: `enables-layout-hud-on-space-change` |
| `focusDim.dim` | bool | `false` | darken every window but the focused one. `.conf`: `dim-other-windows` / `dim_inactive` |
| `focusDim.dimStrength` | 0–1 (or 0–100) | `0.5` | how dark; a value above 1 is read as percent. `.conf`: `dim-strength` |
| `focusDim.blur` | bool | `false` | blur every window but the focused one; combines with dimming. `.conf`: `blur-other-windows` |
| `focusDim.blurRadius` | 1–100 (points) | `20` | rounded to whole points. The Settings slider shows 2–60. `.conf`: `blur-radius` |
| `workspaces.virtual` | bool | `true` | true: CatWM controls native Desktops. false: macOS controls switching. See [workspaces.md](workspaces.md). `.conf`: `virtual-workspaces` |
| `workspaces.stayAfterClose` | bool | `true` | `.conf`: `stay-on-workspace-after-close` |
| `workspaces.removeEmpty` | bool | `true` | true: an empty workspace and its Desktop go away when you leave it. `.conf`: `remove-empty-workspaces` |
| `workspaces.perDisplay` | bool | `true` | true: each display counts its own workspaces from 1, and `workspace 2` selects the second workspace on the current display. false: workspace numbers are shared by all displays. `.conf`: `workspaces-per-display` |
| `workspaces.sortNudge` | 0–100 (whole number) | `5` | windows on one workspace before CatWM offers Overview; `0` turns the offer off. `.conf`: `sort-nudge` |
| `keyboardHelp.enabled` | bool | `true` | on-screen keyboard help in window mode. `.conf`: `keyboard-help` |
| `keyboardHelp.key` | one character | `?` | toggles the keyboard help in window mode. `.conf`: `keyboard-help-key` |
| `keyboardHelp.finish` | `auto`, `macbook-pro`, `macbook-air`, `macbook-neo`, `magic-keyboard`, or a finish such as `macbook-pro-space-black` | `auto` | look of the Shortcut Map keyboard. `.conf`: `keyboard-finish` |
| `cursorActions` | bool | `true` | in window mode, a dot at the pointer; a tap of the mode modifier opens saved workspace templates and the Save workspace action. `.conf`: `cursor-actions` |
| `templateAppScripting` | bool | `false` | workspace templates also save browser tabs, Terminal and iTerm2 tab folders, Finder folders and code editor projects; macOS asks once for each scripted app. `.conf`: `template-app-scripting` |
| `switcher.instantJump` | bool | `true` | in the window switcher, a search with one prefix match opens that window by itself. `.conf`: `switcher-instant-jump` |
| `switcher.jumpDelay` | milliseconds | `300` | wait before instant jump opens the match; `0` opens it at once. `.conf`: `switcher-jump-delay` |
| `switcher.exclude` | bundle IDs, comma separated | `` | apps the window switcher never shows; wildcards like com.adobe.* work. `.conf`: `switcher-exclude` |
| `animation.enabled` | bool | `true` | `animations { enabled = … }` also works. `.conf`: `animate` / `animations` |
| `animation.duration` | seconds, or ms if above 5 | `0.12` | `.conf`: `animation-duration` |
| `animation.curve` | `ease-out` `ease-in-out` `linear` `spring` `bounce` `overshoot` `cubic-bezier(x1, y1, x2, y2)` | `ease-out` | `.conf`: `animation-curve` |
| `animation.bounce` | 0–1 (or 0–100) | `0.5` | liveliness of spring/bounce/overshoot. `.conf`: `animation-bounce` |
| `panelAnimation` | `rise` `pop` `focus` `tile` `draw` | `rise` | how Overview and keyboard help come and go; `tile` follows the animation curve; `catwm panelfx <style>` previews. `.conf`: `panel-animation` |
| `modeEffect` | `draw` `ripple` `corners` `none` | `draw` | visual while window mode is on; `catwm modefx <style>` previews. `.conf`: `mode-effect` |
| `lab.resizeAnimation` | `live` `color-fill` `snapshot` `stream` | `live` | experimental: `live` resizes the real windows each frame, `color-fill` paints the window colors around a smaller real window, `snapshot` animates captured windows, `stream` shows each window's own live capture at its real size; all but `live` need Screen Recording. `.conf`: `resize-animation` |
| `debugLogging` | bool | `false` | verbose log; `--verbose` turns it on for one launch. `.conf`: `debug-logging` |
| `perfReports` | bool | `false` | sends repeated slow animations and hangs (numbers and app bundle IDs only) to the developers. `.conf`: `perf-reports` |
| `binds` | list of `{ mods?, key, run, repeat? }` | | see [keybinds.md](keybinds.md) |
| `submaps` | `{ name: [binds] }` | | key modes |
| `features.<group>.<feature>` | bool | `true` | see `catwm.d.ts` for the list |

## Layout names

`tall`, `tall-right`, `wide`, `middle-wide`, `fullscreen`, `column`, `row`, `floating`, `bsp`, `3column-left`, `3column-middle`, `3column-right`, `two-pane`, `two-pane-right`, `widescreen-tall`, `widescreen-tall-right`.

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
