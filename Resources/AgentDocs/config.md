# Config: `~/.config/ouch/ouch.conf`

Hyprland syntax: `key = value`, `$var = value`, `# comments`, `bind = …` lines, and `name { … }` blocks. Option names are case-insensitive and `-` equals `_` (`window-margin-size` = `window_margin_size`). A `prefix:` is stripped (`general:gaps_in`), so Hyprland configs mostly parse. Unknown options and bad values are logged as `config: …` and skipped; the rest still loads.

Apply changes with `ouch reload`, the menu bar's reload button, or by saving through Settings.

Booleans accept `true yes on 1`; anything else is false.

## Options

| Option | Value | Notes |
|---|---|---|
| `$mod` | `SUPER` / `ALT` / `CTRL` / `SHIFT` | variable used in binds. Default `ALT` |
| `layouts` | comma list | the cycle; each layout once. Names below |
| `window-margins` | bool | gaps between windows |
| `window-margin-size` | number (px) | `gaps_in` is accepted and doubled |
| `smart-window-margins` / `smart-gaps` | bool | no gaps with a single window |
| `screen-padding-left/right/top/bottom` | number | `screen-padding` or `gaps_out` sets all four |
| `disable-padding-on-builtin-display` | bool | |
| `ignore-menu-bar` | bool | |
| `mouse-follows-focus` | bool | |
| `focus-follows-mouse` / `follow_mouse` | bool | |
| `mouse-swaps-windows` | bool | drag a tile onto another to swap |
| `mouse-resizes-windows` | bool | drag edges to resize |
| `floating` | comma list of bundle IDs | apps that float (or the only ones that tile, see next) |
| `floating-is-blacklist` | bool | true: listed apps float. false: only listed apps are tiled |
| `float-small-windows` | bool | |
| `new-windows-to-main` / `new_is_master` | bool | |
| `enables-layout-hud` | bool | HUD when the layout changes |
| `enables-layout-hud-on-space-change` | bool | |
| `window-resize-step` | number | percent (`5`) or fraction (`0.05`); ≥1 is treated as percent |
| `animate` / `animations` | bool | `animations { enabled = … }` also works |
| `animation-duration` | seconds, or ms if >5 | default 0.12 |
| `animation-curve` | `ease-out` `ease-in-out` `linear` `spring` `bounce` `overshoot` `cubic-bezier(x1, y1, x2, y2)` | |
| `animation-bounce` | 0–1 (or 0–100) | liveliness of spring/bounce/overshoot |
| `virtual-workspaces` | bool | true: Ouch workspaces. false: macOS Spaces. See [workspaces.md](workspaces.md) |
| `stay-on-workspace-after-close` | bool | default true |
| `debug-logging` | bool | verbose log; prefer `--verbose` |
| `keyboard-help` | bool | |
| `keyboard-finish` | `auto`, `macbook-pro`, `macbook-air`, `macbook-neo`, `magic-keyboard`, or a finish such as `macbook-pro-space-black` | look of the Shortcut Map keyboard |
| `mode-effect` | `draw` `ripple` `corners` `none` | visual while window mode is on; `ouch modefx <style>` previews |
| `panel-animation` | `rise` `pop` `focus` `tile` `draw` | how Sort Windows and keyboard help come and go; `tile` follows the animation curve; `ouch panelfx <style>` previews |
| `dim-other-windows` | bool | darken every window but the focused one (`dim_inactive` works too) |
| `dim-strength` | 0–1 | how dark; default 0.3 |
| `blur-other-windows` | bool | blur every window but the focused one; combines with dimming |
| `blur-radius` | points | default 20 |
| `bind` (also `binde`, `bindr`, `bindl`, `bindel`, `bindle`) | see [keybinds.md](keybinds.md) | the `binde`/`bindel`/`bindle` forms repeat while held |
| `submap = name` / `submap = reset` | | groups binds into a mode |

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
