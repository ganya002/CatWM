# Keybinds

A bind is a `catwm.bind(mods, key, run, options?)` call. Put the calls at the top level of the config:

```ts
import { catwm } from "./catwm"

catwm.bind(["alt", "shift"], "tab", ["switcher", "prev"])
catwm.bind([], "h", ["movefocus", "l"], { repeat: true, submap: "window" })   // no mods: only in a mode
catwm.bind(["alt"], "o", "sort")                                               // an action with no arguments
catwm.bind(["alt"], "c", () => catwm.window.focused.float())                   // a function that acts on the focused window
```

- `mods`: any of `"cmd"`, `"alt"`, `"ctrl"`, `"shift"`. Leave it out in a mode. A constant such as `const mod = "alt"` works: `[mod, "shift"]`.
- `key`: a letter, digit, `f1`–`f12`, `space`, `return`, `escape`, `backspace`, arrows (`left right up down`), `capslock`, and so on, plus the scroll and swipe keys below. `catwm.d.ts` lists them all.
- `run`: an action name, or the name and its arguments. The arguments are the ones the `.conf` file used after the dispatcher. [dispatchers.md](dispatchers.md) lists every action.
- `{ repeat: true }` runs the action again while the key is held. `{ submap: "name" }` puts the bind in a mode.
- A function runs when the key is pressed. `catwm.window.focused` has `title`, `app`, `pid` and `frame`, and the methods `float()`, `tile()`, `resize(w, h)`, `move(x, y)`, `center()`, `fullscreen()` and `moveTo(workspace)`. A function that throws, or runs longer than the time limit, does nothing and shows an error like a broken config.
- The macOS app-shortcut caveat: binding `cmd` combos like Q or C replaces the standard app shortcut. Settings → Shortcuts flags those in orange.

## Many keys at once

There's no range syntax. Write ordinary TypeScript:

```ts
import { catwm } from "./catwm"

for (const [index, key] of ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].entries()) {
  catwm.bind(["alt"], key, ["workspace", String(index + 1)])
}
for (const [index, key] of (["h", "j", "k", "l"] as const).entries()) {
  catwm.bind(["alt", "ctrl"], key, ["movefocus", "ldur"[index]])
}
```

## The old `.conf` syntax

`catwm.conf` used `bind = MODS, key, dispatcher, args` lines with `$vars`, ranges (`1..0`) and lists (`h|j|k|l`). The first launch converts it: variables become constants and each range becomes one bind for each key.

## Window mode (submaps)

```ts
catwm.bind(["cmd"], "capslock", ["submap", "window"])   // enter the mode (Caps Lock itself is left alone)
catwm.bind([], "h", ["movefocus", "l"], { submap: "window" })
catwm.bind(["shift"], "h", ["movewindow", "l"], { submap: "window" })
catwm.bind([], "escape", ["submap", "reset"], { submap: "window" })
```

- While on, "-- WINDOW --" appears at the screen bottom and the menu bar shows WINDOW.
- Keys with no bind in the mode are swallowed. ⌘ and ⌃ shortcuts still reach apps.
- Clicking anywhere leaves the mode, except a right click on a window: it opens that window's context menu and the mode stays on.
- Always give the mode an exit (`["submap", "reset"]`) or the user gets stuck.
- Mode names are free-form; `window` is what the UI's "Window mode" tab edits.

## Scroll and swipes

Keys: `mouse_up`, `mouse_down`, `mouse_left`, `mouse_right`; `swipe_left`, `swipe_right`, `swipe_up`, `swipe_down`.

```ts
catwm.bind(["alt"], "mouse_down", ["workspace", "e+1"])
catwm.bind(["alt", "ctrl"], "swipe_left", ["workspace", "+1"])
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
