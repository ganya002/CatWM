# Keybinds

A bind is a typed object in `binds` (every app) or in a mode of `submaps`:

```ts
{ mods: ["alt", "shift"], key: "tab", run: ["switcher", "prev"] }
{ key: "h", run: ["movefocus", "l"], repeat: true }   // no mods: only in a mode
{ mods: ["alt"], key: "o", run: "sort" }               // an action with no arguments
```

- `mods`: any of `"cmd"`, `"alt"`, `"ctrl"`, `"shift"`. Leave it out in a mode. A constant such as `const mod = "alt"` works: `mods: [mod, "shift"]`.
- `key`: a letter, digit, `f1`–`f12`, `space`, `return`, `escape`, `backspace`, arrows (`left right up down`), `capslock`, and so on, plus the scroll and swipe keys below. `catwm.d.ts` lists them all.
- `run`: an action name, or the name and its arguments. The arguments are the ones the `.conf` file used after the dispatcher. [dispatchers.md](dispatchers.md) lists every action.
- `repeat: true` runs the action again while the key is held.
- The macOS app-shortcut caveat: binding `cmd` combos like Q or C replaces the standard app shortcut. Settings → Shortcuts flags those in orange.

## Many keys at once

There's no range syntax. Write ordinary TypeScript:

```ts
import type { Bind } from "./catwm"
const keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] as const
const workspaces = keys.map((key, index): Bind => ({ mods: ["alt"], key, run: ["workspace", String(index + 1)] }))
const focus = (["h", "j", "k", "l"] as const).map((key, index): Bind =>
  ({ mods: ["alt", "ctrl"], key, run: ["movefocus", "ldur"[index]] }))
export default { binds: [...workspaces, ...focus] }
```

## The old `.conf` syntax

`catwm.conf` used `bind = MODS, key, dispatcher, args` lines with `$vars`, ranges (`1..0`) and lists (`h|j|k|l`). The first launch converts it: variables become constants and each range becomes one bind for each key.

## Window mode (submaps)

```ts
binds: [
  { mods: ["cmd"], key: "capslock", run: ["submap", "window"] },   // enter the mode (Caps Lock itself is left alone)
],
submaps: {
  window: [
    { key: "h", run: ["movefocus", "l"] },
    { mods: ["shift"], key: "h", run: ["movewindow", "l"] },
    { key: "escape", run: ["submap", "reset"] },
  ],
},
```

- While on, "-- WINDOW --" appears at the screen bottom and the menu bar shows WINDOW.
- Keys with no bind in the mode are swallowed. ⌘ and ⌃ shortcuts still reach apps.
- Clicking anywhere leaves the mode, except a right click on a window: it opens that window's context menu and the mode stays on.
- Always give the mode an exit (`["submap", "reset"]`) or the user gets stuck.
- Mode names are free-form; `window` is what the UI's "Window mode" tab edits.

## Scroll and swipes

Keys: `mouse_up`, `mouse_down`, `mouse_left`, `mouse_right`; `swipe_left`, `swipe_right`, `swipe_up`, `swipe_down`.

```ts
{ mods: ["alt"], key: "mouse_down", run: ["workspace", "e+1"] }
{ mods: ["alt", "ctrl"], key: "swipe_left", run: ["workspace", "+1"] }
```

- Matched scrolls are consumed; unmatched ones reach the app. Direction follows natural-scrolling.
- Trackpad scroll fires once per short burst; momentum after lift-off is ignored.
- Swipes can't be intercepted: macOS's own gesture still fires. Disable it in System Settings → Trackpad → More Gestures, or use another finger count. The "Swipe between pages / full-screen apps" gestures must be enabled for swipes to be reported.

## Defaults

The stock config (`mod` = Option) has these binds. Read the user's `catwm.config.ts` and `catwm.overrides.json` before you think a bind exists. **Restore Defaults** (Settings → Shortcuts) resets the binds.

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
