# mxtiler

A small Amethyst-style tiling window manager for macOS with Hyprland-style keybinds and animated window movement.

## Build & run

```sh
./build.sh
open build/mxtiler.app
```

On first launch, grant **Accessibility** in System Settings → Privacy & Security. The app is ad-hoc signed, so after each rebuild you may need to remove and re-add it there.

## Releasing with Amore

Updates ship through [Amore](https://amore.computer) and Sparkle. Amore signs, notarizes, builds the DMG, writes the appcast and hosts it.

One-time setup:

```sh
amore login
./build.sh
amore setup build/mxtiler.app --hosting amore --generate-sparkle-key
```

Put the feed URL and public key it prints into `SUFeedURL` and `SUPublicEDKey` in `Info.plist`. Until you do, the app has no update checks.

Each release: bump `CFBundleVersion` in `Info.plist`, then

```sh
./release.sh "What changed"                      # build, sign, notarize, publish
./release.sh "Try this first" --channel beta     # beta channel (Settings → Include beta releases)
./release.sh "Security fix" --critical           # prompts users to update right away
./release.sh "Big change" --phased-rollout       # gradual rollout
./release.sh "WIP" --draft                       # upload without publishing
```

Settings → Overview has the update toggles, and the menu bar has **Check for Updates…**.

## Config

`~/.config/mxtiler/mxtiler.conf` is created on first run. The menu bar icon has buttons to open and reload it.

It uses Hyprland syntax (`$vars`, `bind = MODS, key, dispatcher, args`, `general { }` blocks) with Amethyst's options (`layouts`, `window-margin-size`, `screen-padding-*`, `mouse-follows-focus`, `focus-follows-mouse`, `mouse-swaps-windows`, `mouse-resizes-windows`, `floating`, `floating-is-blacklist`, `float-small-windows`, `new-windows-to-main`, `enables-layout-hud`, `ignore-menu-bar`, `window-resize-step`, …). It also adds `animate` and `animation-duration`.

The default `$mod` is **Option**, so your app shortcuts like ⌘Q and ⌘C keep working. Set `$mod = SUPER` to use Command like Hyprland does.

### Window mode (submaps)

Binds can live in a mode, like Hyprland's submaps or vim's normal mode. A global shortcut enters the mode, and inside it single keys do the work. Outside the mode those keys reach your apps untouched, so vim keeps working.

```
bind = SUPER, capslock, submap, window  # ⌘Caps Lock enters window mode (Caps Lock itself is left alone)
submap = window
bind = , h|j|k|l, movefocus, l|d|u|r
bind = SHIFT, h|j|k|l, movewindow, l|d|u|r
bind = , 1..0, workspace, 1..10
bind = , escape|i|return, submap, reset
submap = reset
```

- While a mode is on, "-- WINDOW --" shows at the bottom of the screen and the menu bar shows WINDOW.
- Keys with no bind in the mode are ignored instead of typed. ⌘ and ⌃ shortcuts still reach the app.
- Clicking anywhere leaves the mode.
- In Settings → Keyboard Shortcuts, switch between **Global** and **Window mode** to edit each set.

### Range binds

One line can bind a run of keys. The values are paired with the keys in order.

```
bind = $mod, 1..0, workspace, 1..10               # number-row order: ⌥1…⌥9 → 1–9, ⌥0 → 10
bind = $mod SHIFT, 1..0, movetoworkspace, 1..10
bind = $mod, f1..f4, layout, tall|wide|bsp|column  # a list works too
bind = $mod CTRL, h|j|k|l, movefocus, l|d|u|r
bind = $mod, a..d, layout, bsp                     # one value is used for every key
```

`exec` arguments are never expanded.

### Scroll wheel and trackpad swipes

Scrolling and swipes are keys in `bind` lines, so they work with modifiers, ranges and window mode like any other bind.

```
bind = $mod, mouse_down, workspace, e+1        # hold ⌥ and scroll down: next workspace with windows
bind = $mod, mouse_up, workspace, e-1
bind = $mod SHIFT, mouse_down, cyclenext
bind = $mod CTRL, swipe_left, workspace, +1    # trackpad swipe
```

- Keys: `mouse_up`, `mouse_down`, `mouse_left`, `mouse_right` (scroll) and `swipe_left`, `swipe_right`, `swipe_up`, `swipe_down`.
- Scrolls without a matching bind reach your apps as usual. A matching scroll is taken, so the app under the pointer doesn't scroll too. Directions follow the system's natural-scrolling setting.
- A trackpad scroll fires once per short stretch of movement, and the momentum after you lift off is ignored.
- Swipes can't be intercepted, so macOS's own gesture for the same swipe still happens. Turn it off in System Settings → Trackpad → More Gestures, or use a finger count macOS doesn't use. Swipes need the "Swipe between pages / full-screen apps" gestures enabled to be reported at all.

### Workspaces

mxtiler has its own workspaces, like Hyprland and AeroSpace, so switching and moving windows are instant:

- Each display shows one workspace. A workspace remembers its layout and its last focused window.
- Windows on hidden workspaces are parked just off-screen in a corner of their display; macOS won't let a window go fully off-screen.
- If you ⌘-Tab or click the Dock to a window on a hidden workspace, mxtiler switches to that workspace.
- The menu bar shows ① ② ❸; the filled number is the workspace you're on. Click it to pick a workspace.
- `workspace` accepts `N`, `name:foo`, `previous`, `+1` / `-1` and `e+1` / `e-1` (the next workspace that has windows). `movetoworkspace` follows the window; `movetoworkspacesilent` doesn't.
- Workspaces live on one **home Desktop** per display: the macOS Desktop you were on at first launch, or the one chosen in Settings → Behavior. Other Desktops tile normally, and ⌘1–0 from one of them goes home first. This setup works best with a single macOS Desktop.
- When mxtiler quits, crashes or is killed, every parked window is put back on screen, and assignments are saved for the next launch.
- To use macOS Spaces instead, set `virtual-workspaces = false`. Space switching then uses "Switch to Desktop N" when it's on, and otherwise steps with Ctrl-←/→.

### Dispatchers

| Dispatcher | Args |
|---|---|
| `movefocus` | `l r u d` |
| `movewindow` / `swapwindow` | `l r u d`, or `mon:l`, `mon:+1`, `mon:0` |
| `cyclenext` / `swapnext` | *(none)* or `prev` |
| `layoutmsg` | `swapwithmaster`, `focusmaster`, `addmaster`, `removemaster`, `mfact ±0.05`, `orientationnext`/`prev` |
| `splitratio` | `+0.05`, `-0.05`, `exact 0.6` |
| `togglefloating`, `fullscreen`, `killactive`, `exit` | |
| `exec` | shell command |
| `focusmonitor` | `l r u d`, `+1`, `-1`, index |
| `workspace` / `movetoworkspace` | `1`–`10` (requires macOS's "Switch to Desktop N" shortcuts on Ctrl+N) |
| `cyclelayout` | `next` / `prev` |
| `layout` | layout name, e.g. `bsp` |
| `toggletiling`, `retile`, `reload` | |

## Tiling fixes compared to Amethyst

- Frames are set size → position → size, so windows moving to a smaller or offset display aren't clamped into the wrong slot.
- `AXEnhancedUserInterface`, which Magnet, Rectangle, Grammarly and VoiceOver turn on, is switched off while windows move. Those apps otherwise ignore new frames or animate them wrongly.
- Every frame is checked after it settles and retried once. A window with a minimum size larger than its slot is kept on screen, aligned with its slot.
- Windows that an app moves itself after opening get a second pass and are snapped back. Snap-back gives up after three tries so it can't loop.
- Slot edges are rounded independently, so there are never 1px gaps or overlaps between windows.
- Windows on the current space come from the CoreGraphics window list instead of AX alone. Windows on other spaces and minimized windows no longer leave holes in the layout.
- Windows that can't be resized float automatically instead of breaking the layout.

## Settings window

Open it from the menu bar icon with **Settings…**. Changes save and apply automatically, and **Undo All Changes** goes back to how things were when you opened the window.

- **Overview:** permission and keybind status, a layout picker for each display, and quick toggles
- **Layouts:** clickable layout cards and the cycle order
- **Gaps & Padding:** a preview drawn at your real screen's proportions
- **Behavior:** focus follows mouse, mouse follows focus, drag to swap or resize, new windows, layout HUD
- **Floating Windows:** apps that float or are the only ones tiled, with a picker for running apps
- **Animation:** speed presets and a preview
- **Keyboard Shortcuts:** grouped by category with readable action names. Click a shortcut, then press the new keys to record it. Invalid shortcuts are flagged in red; ones that replace a standard app shortcut like ⌘Q are flagged in orange.
- **Advanced:** config and log files, detailed logging, command-line usage, and resets

## Command line

```sh
build/mxtiler.app/Contents/MacOS/mxtiler dispatch movefocus l
build/mxtiler.app/Contents/MacOS/mxtiler dump      # writes tiling state to ~/Library/Logs/mxtiler.log
build/mxtiler.app/Contents/MacOS/mxtiler reload
```

`exec` only works from keyboard shortcuts, not from the command line.

## Rebuilding

The app is ad-hoc signed, so every rebuild cancels its Accessibility permission. mxtiler notices this, shows a ⚠️ in the menu bar, and opens Settings. Click **Reset Permission** there, then turn mxtiler on again.
