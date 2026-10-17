# Config: `~/.config/ouch/ouch.conf`

Hyprland syntax: `key = value`, `$var = value`, `# comments`, `bind = …` lines, and `name { … }` blocks. Option names are case-insensitive and `-` equals `_` (`window-margin-size` = `window_margin_size`). A `prefix:` is stripped (`general:gaps_in`), so Hyprland configs mostly parse. Unknown options and bad values are logged as `config: …` and skipped; the rest still loads.

Apply changes with `ouch reload`, the menu bar's reload button, or by saving through Settings.

Booleans accept `true yes on 1` and `false no off 0`. Any other value is an error: Ouch logs it and the option becomes false. A bad number or name is also an error, and the option keeps its earlier value (the default, if no earlier line sets it). Numbers outside the range in the table are clamped to that range.

## Options

The Settings window writes options in this order. Aliases (after `/`) are read but never written.

| Option | Value | Default | Notes |
|---|---|---|---|
| `$mod` | `SUPER` / `ALT` / `CTRL` / `SHIFT` | `ALT` | variable used in binds |
| `layouts` | comma list | `{{default-layouts}}` | the cycle; each layout once. Names below |
| `floating` | comma list of bundle IDs | empty (first run: System Settings, Calculator) | apps that float (or the only ones that tile, see next). Wildcards such as `com.adobe.*` work |
{{options}}
| `bind` (also `binde`, `bindr`, `bindl`, `bindel`, `bindle`) | see [keybinds.md](keybinds.md) | | the `binde`/`bindel`/`bindle` forms repeat while held |
| `submap = name` / `submap = reset` | | | groups binds into a mode |

The animation options (`animate`, `animation-duration`, `animation-curve`, `animation-bounce`) make up an animation config (see below).

`bindm` is accepted and ignored (dragging already moves and resizes tiles).

## Layout names

{{layouts}}.

## Minimal example

```
$mod = ALT
layouts = tall, bsp, fullscreen
window-margin-size = 10
screen-padding = 10
animate = true
animation-curve = spring
animation-bounce = 0.6
floating = com.apple.systempreferences, com.apple.calculator
floating-is-blacklist = true

bind = $mod, 1..0, workspace, 1..10
bind = $mod SHIFT, 1..0, movetoworkspace, 1..10
bind = $mod, return, exec, open -na Terminal
```

## Settings window and saved configs

Menu bar → **Settings…** (⌘,). Panes: General, Layout, Windows, Motion, Templates, Shortcuts. Changes save and apply automatically. **Configs** (menu bar submenu / Settings) stores named keyboard, animation, and full presets in `~/.config/ouch/configs.json`; switching one rewrites the matching part of `ouch.conf`. Presets can be imported and exported.

When editing by hand while the app runs, make the edit then run `ouch reload`. If the user also has Settings open, tell them: UI edits can overwrite hand edits.

## Workspace templates

Settings → **Templates** lists saved workspaces with large screenshot previews. Click a screenshot to enlarge it. Open, rename, update, or delete a template here. A template stores app identities, document addresses when available, window frames, display sizes, layouts, main-pane ratios and counts, window order, tiling status, and floating, minimized, zoomed, or native full screen states. Templates are stored in `~/.config/ouch/templates.json`, separately from configs. Screenshots are stored in that file. Screen recording access is required to capture them. Saving still works without that access. Update an older template to add a screenshot.

In window mode, tap the mode modifier to open quick actions at the pointer. Press **S** to show a name field beside Save. Type the name and press Return to save without opening Settings. The screenshot can finish after the template saves. Escape cancels naming and returns to the action list. Press **1–9** to open a saved template. Hover a template to replace its number with an X. Click the X to delete it without closing the menu. Arrow keys and Return select an action. These actions also work over empty desktop space.

Quick actions also retain the focus controls: **D** toggles Dim other windows, and **B** toggles Blur other windows.

Restore reuses matching windows in the current workspace, opens missing apps or supplied documents, and requests new windows from apps that support them. Missing displays use available displays. Frames scale to fit. Existing extra windows stay open. Tabs, unsaved work, and other internal app state are not saved. Ouch reports windows that it cannot open or position.
