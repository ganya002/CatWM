# Keybinds

```
bind = MODS, key, dispatcher, args
```

- `MODS`: space-separated, any of `SUPER` (= `CMD`, `COMMAND`, `WIN`, `META`, `MOD4`), `ALT` (= `OPT`, `OPTION`, `MOD1`), `CTRL` (= `CONTROL`), `SHIFT`. May be empty (`bind = , h, …`), as in window mode. `$mod` and other `$vars` expand.
- `key`: a letter, digit, `f1`–`f20`, `space`, `return`, `escape`/`esc`, `backspace`, arrows (`left right up down`), `capslock`/`caps`, and so on, plus the scroll and swipe keys below.
- The macOS app-shortcut caveat: binding `SUPER` combos like Q or C replaces the standard app shortcut. Settings → Shortcuts flags those in orange.

## Ranges and lists

One line binds many keys; values pair with keys in order.

```
bind = $mod, 1..0, workspace, 1..10                 # ⌥1…⌥9 → 1–9, ⌥0 → 10
bind = $mod, f1..f4, layout, tall|wide|bsp|column   # a | list works too
bind = $mod CTRL, h|j|k|l, movefocus, l|d|u|r
bind = $mod, a..d, layout, bsp                      # one value is used for every key
```

`exec` arguments and any argument containing spaces are never expanded.

## Window mode (submaps)

```
bind = SUPER, capslock, submap, window   # enter the mode (Caps Lock itself is left alone)
submap = window
bind = , h|j|k|l, movefocus, l|d|u|r
bind = SHIFT, h|j|k|l, movewindow, l|d|u|r
bind = , 1..0, workspace, 1..10
bind = , escape|i|return, submap, reset
submap = reset
```

- While on, "-- WINDOW --" appears at the screen bottom and the menu bar shows WINDOW.
- Keys with no bind in the mode are swallowed. ⌘ and ⌃ shortcuts still reach apps.
- Clicking anywhere leaves the mode, except a right click on a window: it opens that window's context menu and the mode stays on.
- Always give the mode an exit (`submap, reset`) or the user gets stuck.
- Mode names are free-form; `window` is what the UI's "Window mode" tab edits.

## Scroll and swipes

Keys: `mouse_up`, `mouse_down`, `mouse_left`, `mouse_right`; `swipe_left`, `swipe_right`, `swipe_up`, `swipe_down`.

```
bind = $mod, mouse_down, workspace, e+1
bind = $mod CTRL, swipe_left, workspace, +1
```

- Matched scrolls are consumed; unmatched ones reach the app. Direction follows natural-scrolling.
- Trackpad scroll fires once per short burst; momentum after lift-off is ignored.
- Swipes can't be intercepted: macOS's own gesture still fires. Disable it in System Settings → Trackpad → More Gestures, or use another finger count. The "Swipe between pages / full-screen apps" gestures must be enabled for swipes to be reported.

## Defaults

The stock config (`$mod` = Option) has these binds. Read the user's actual file before you think a bind exists. **Restore Defaults** (Settings → Shortcuts) resets the binds.

Global binds:

- `CTRL`+`1..0` and `CTRL`+`left|right`: show a workspace. Add `SHIFT` to move the focused window there.
- `$mod`+`O`: Overview (`sort`). `$mod`+`Tab` and `$mod SHIFT`+`Tab`: window switcher.
- `SUPER`+`Caps Lock`: window mode.
- `$mod CTRL`+`H|J|K|L`: focus a neighbour. Add `SHIFT` to move the window.
- `$mod CTRL`+`F`: `fullscreen`. `$mod CTRL`+`V`: `togglefloating`.

Window mode (Vim set):

- `H J K L` and arrows: focus. `SHIFT`: move. `1..0`: workspace. `SHIFT`+`1..0`: move to workspace.
- `W` / `B`: next or previous display. `SHIFT`: move the window there.
- `N` / `P` and `S` / `SHIFT S`: next or previous layout.
- `,` / `.`: main pane size. `SHIFT`: main count. `M`: swap with main. `SHIFT M`: swap sides. `G`: focus main.
- `Tab` / `SHIFT Tab`: next or previous window. `CTRL`+`H|J|K|L`: into a tab group. `T`: out of the group. `[` / `]`: tabs.
- `F`: `fullscreen`. `SHIFT F`: macOS full screen. `V`: float. `X`: close. `-`: minimise.
- `O`: Overview. `/`: window switcher. `` ` ``: previous workspace.
- `D`: dim other windows. `SHIFT D`: blur other windows.
- `Z`: retile. `SHIFT T`: pause tiling. `SHIFT R`: reload. `Esc`, `I`, `Return`: leave the mode.

The WASD set uses `W A S D` for focus, `Q E` for workspaces, `R` for layouts, `C` to float and `G` to swap with main. It has `O`, `/`, `` ` ``, `X` and `-` too, but no keys for dim, blur, focus main and the `S` layout keys.
