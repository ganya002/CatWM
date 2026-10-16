# Config: `~/.config/ouch/ouch.conf`

Hyprland syntax: `key = value`, `$var = value`, `# comments`, `bind = …` lines, and `name { … }` blocks. Option names are case-insensitive and `-` equals `_` (`window-margin-size` = `window_margin_size`). A `prefix:` is stripped (`general:gaps_in`), so Hyprland configs mostly parse. Unknown options and bad values are logged as `config: …` and skipped; the rest still loads.

Apply changes with `ouch reload`, the menu bar's reload button, or by saving through Settings.

Booleans accept `true yes on 1` and `false no off 0`. Any other value is an error: Ouch logs it and the option becomes false. A bad number or name is also an error, and the option keeps its earlier value (the default, if no earlier line sets it). Numbers outside the range in the table are clamped to that range.

## Options

The Settings window writes options in this order. Aliases (after `/`) are read but never written.

| Option | Value | Default | Notes |
|---|---|---|---|
| `$mod` | `SUPER` / `ALT` / `CTRL` / `SHIFT` | `ALT` | variable used in binds |
| `layouts` | comma list | `tall, wide, fullscreen, bsp, column` | the cycle; each layout once. Names below |
| `floating` | comma list of bundle IDs | empty (first run: System Settings, Calculator) | apps that float (or the only ones that tile, see next). Wildcards such as `com.adobe.*` work |
| `floating-is-blacklist` | bool | `true` | true: listed apps float. false: only listed apps are tiled |
| `window-margins` | bool | `true` | gaps between windows |
| `window-margin-size` | number (points) | `10` | `gaps_in` is accepted and doubled |
| `smart-window-margins` / `smart-gaps` | bool | `false` | no gaps with a single window |
| `screen-padding-left` | number (points) | `10` | `screen-padding` or `gaps_out` sets all four sides |
| `screen-padding-right` | number (points) | `10` | |
| `screen-padding-top` | number (points) | `10` | |
| `screen-padding-bottom` | number (points) | `10` | |
| `disable-padding-on-builtin-display` | bool | `false` | |
| `ignore-menu-bar` | bool | `false` | tile over the menu bar area |
| `mouse-follows-focus` | bool | `false` | |
| `focus-follows-mouse` / `follow_mouse` | bool | `false` | |
| `focus-follows-mouse-in-mode-only` | bool | `false` | with `focus-follows-mouse` on, hovering focuses a window only while window mode is on |
| `mouse-swaps-windows` | bool | `true` | drag a tile onto another to swap |
| `mouse-resizes-windows` | bool | `true` | drag edges to resize |
| `new-windows-to-main` / `new_is_master` | bool | `false` | |
| `float-small-windows` | bool | `true` | |
| `window-resize-step` | number | `5` | percent (`5`) or fraction (`0.05`); 1 or more is read as percent |
| `enables-layout-hud` | bool | `true` | HUD when the layout changes |
| `enables-layout-hud-on-space-change` | bool | `true` | |
| `dim-other-windows` / `dim_inactive` | bool | `false` | darken every window but the focused one |
| `dim-strength` | 0–1 (or 0–100) | `0.3` | how dark; a value above 1 is read as percent |
| `blur-other-windows` | bool | `false` | blur every window but the focused one; combines with dimming |
| `blur-radius` | 1–100 (points) | `20` | rounded to whole points. The Settings slider shows 2–60 |
| `virtual-workspaces` | bool | `true` | true: Ouch workspaces. false: macOS Spaces. See [workspaces.md](workspaces.md) |
| `stay-on-workspace-after-close` | bool | `true` | |
| `sort-strategy` | `task` `app` `focus` `none` | `task` | the grouping Sort Windows opens with |
| `sort-nudge` | 0–100 (whole number) | `5` | windows on one workspace before Ouch offers to sort them; `0` turns the offer off |
| `keyboard-help` | bool | `true` | on-screen keyboard help in window mode |
| `keyboard-help-key` | one character | `?` | toggles the keyboard help in window mode |
| `keyboard-finish` | `auto`, `macbook-pro`, `macbook-air`, `macbook-neo`, `magic-keyboard`, or a finish such as `macbook-pro-space-black` | `auto` | look of the Shortcut Map keyboard |
| `cursor-actions` | bool | `true` | in window mode, a dot at the pointer; a tap of the mode's modifier opens actions for the window under it |
| `animate` / `animations` | bool | `true` | `animations { enabled = … }` also works |
| `animation-duration` | seconds, or ms if above 5 | `0.18` | |
| `animation-curve` | `ease-out` `ease-in-out` `linear` `spring` `bounce` `overshoot` `cubic-bezier(x1, y1, x2, y2)` | `ease-out` | |
| `animation-bounce` | 0–1 (or 0–100) | `0.5` | liveliness of spring/bounce/overshoot |
| `panel-animation` | `rise` `pop` `focus` `tile` `draw` | `rise` | how Sort Windows and keyboard help come and go; `tile` follows the animation curve; `ouch panelfx <style>` previews |
| `mode-effect` | `draw` `ripple` `corners` `none` | `draw` | visual while window mode is on; `ouch modefx <style>` previews |
| `debug-logging` | bool | `false` | verbose log; prefer `--verbose` |
| `perf-reports` | bool | `false` | sends repeated slow animations and hangs (numbers and app bundle IDs only) to the developers |
| `bind` (also `binde`, `bindr`, `bindl`, `bindel`, `bindle`) | see [keybinds.md](keybinds.md) | | the `binde`/`bindel`/`bindle` forms repeat while held |
| `submap = name` / `submap = reset` | | | groups binds into a mode |

The animation options (`animate`, `animation-duration`, `animation-curve`, `animation-bounce`) make up an animation config (see below).

`bindm` is accepted and ignored (dragging already moves and resizes tiles).

## Layout names

`tall`, `tall-right`, `wide`, `middle-wide`, `fullscreen`, `column`, `row`, `floating`, `bsp`, `3column-left`, `3column-middle`, `3column-right`, `two-pane`, `two-pane-right`, `widescreen-tall`, `widescreen-tall-right`.

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

Menu bar → **Settings…** (⌘,). Panes: General, Layout, Windows, Motion, Shortcuts. Changes save and apply automatically. **Configs** (menu bar submenu / Settings) stores named keyboard, animation, and full presets in `~/.config/ouch/configs.json`; switching one rewrites the matching part of `ouch.conf`. Presets can be imported and exported.

When editing by hand while the app runs, make the edit then run `ouch reload`. If the user also has Settings open, tell them: UI edits can overwrite hand edits.
