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

The stock config binds `$mod`+`1..0` to workspaces, `SUPER`+`Caps Lock` to window mode, and `$mod`+`T` to `open -na Kitty`. Read the user's actual file before assuming; **Restore Defaults** (Settings → Shortcuts) resets binds.
