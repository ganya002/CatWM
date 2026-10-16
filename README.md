# Ouch

An Amethyst-style tiling window manager for macOS with Hyprland-style keybinds and animated window movement.

## Build & run

```sh
./build.sh
open build/ouch.app
```

For fast rebuilds while you work, run `./build.sh --dev`. It makes a debug build in a few seconds, not about a minute. Do not ship it.

To install a beta build to `/Applications/Ouch.app` and open it, run `./install.sh`. Add `--stable` to skip the beta channel marker.

Testers install with one command. The script is [website/public/install.sh](website/public/install.sh). The website serves it at `https://ouch.perwko.com/install.sh`. Without a flag it installs the latest stable release. With `--beta` it installs the latest beta:

```sh
curl -fsSL https://ouch.perwko.com/install.sh | sh -s -- --beta
```

On first launch, a short intro plays, then a welcome card asks for **Accessibility** (System Settings → Privacy & Security), lets you pick **Vim** (H J K L) or **WASD** keys, and starts a keyboard tour. The tour opens practice windows on a free workspace and tiles them for real; your own windows wait on their workspace until it ends. `open build/ouch.app --args --onboarding` plays it again.

The menu bar has two lessons on the same practice windows:

- **Keyboard Tutorial…** is the long one: chapters (window mode, focus, moving, the main pane, layouts, zoom and float, workspaces, global keys, displays, sorting), each followed by drills you answer from memory. **Pause** remembers the chapter; the menu then reads **Resume Tutorial…**.
- **Help › Quick Tour** replays the onboarding tour.

After onboarding, small tips turn up once each where they help: beside a Settings pane, above the mode bar, or under the menu bar item after you click a command that has a key. **Help › Show Tips** turns them off and on (turning them on shows them again).

The app is ad-hoc signed, so after each rebuild you may need to remove and re-add it in Accessibility.

## Feedback

The ladybug button at the foot of the Settings sidebar opens **Send feedback**, a sheet on the Settings window. The user writes a description. Ouch sends it with its recent log, the config, the Mac's setup and (after a crash) the macOS crash report. The sheet tells the user what it sends.

**Send** files the feedback as a Linear issue through the relay in `report-relay/`, a Cloudflare Worker that holds the Linear API key, since a key shipped inside the app could be pulled out. Deploy it once:

```sh
cd report-relay
npx wrangler deploy
npx wrangler secret put LINEAR_API_KEY   # Linear → Settings → Security & access → Personal API keys
```

Set `LINEAR_TEAM_ID` in `wrangler.toml` to the team's UUID, and put the worker's URL plus `/report` into `OuchReportURL` in `Info.plist`.

## Performance reports

`PerfMonitor` (`Sources/ouch/App/PerfMonitor.swift`) times Ouch's frames while it moves other apps' windows and plays its own panels, the AX cost per app, and main-thread hangs over 250 ms. Every slowdown goes to `ouch.log` as a `perf:` line. With `perf-reports = true` in the config (off by default), a slowdown seen 5 times (a hang over 1 s: twice) is sent to the relay's `/perf` route. The payload holds numbers, the Ouch and macOS version, the Mac model and the slow app's bundle ID. It holds no window titles, paths or names. Runs on a hot, low-power or loaded Mac are logged but never sent. Each fingerprint is sent once per 7 days, at most once a day and 5 a week.

The relay files one Linear issue per fingerprint (`[perf:<id>]` in the title) and adds a comment for each repeat, up to 10. Its API key needs the read and create comment scopes besides create issues. Set `LINEAR_PERF_LABEL_ID` to label the issues.

If Ouch crashes, a small watchdog reopens it once macOS has written the crash report. Nothing pops up: Ouch sends the crash report, the log up to the crash, the config and the Mac's setup to the relay on its own. If the send fails, it tries again on the next launch. `open build/ouch.app --args --crash-report` sends the newest crash report, to test the upload.

## Releasing with Amore

Updates ship through [Amore](https://amore.computer) and Sparkle. Amore signs, notarizes, builds the DMG, writes the appcast and hosts it.

One-time setup:

```sh
amore login
./build.sh
amore setup build/ouch.app --hosting amore --generate-sparkle-key
```

Put the feed URL and public key it prints into `SUFeedURL` and `SUPublicEDKey` in `Info.plist`. Until you do, the app has no update checks.

Each release (the build number is stamped from the commit count, so only `CFBundleShortVersionString` needs a manual bump):

```sh
./release.sh "What changed"                      # build, sign, notarize, publish
./release.sh "Try this first" --channel beta     # beta channel (Settings → General → Updates → Include beta releases)
./release.sh "Security fix" --critical           # prompts users to update right away
./release.sh "Big change" --phased-rollout       # gradual rollout
./release.sh "WIP" --draft                       # upload without publishing
```

For early-access betas, `./beta.sh "What changed"` publishes to the beta channel with no version bump: the build number is the commit count and the version reads `0.2-beta.<build>`. Beta builds start opted in to beta updates. Without a Developer ID certificate it ships an unsigned ZIP, so testers allow it once in System Settings → Privacy & Security → **Open Anyway**.

Settings → General has the update toggles, and the menu bar menu has **Help › Check for Updates…**.

## Config

`~/.config/ouch/ouch.conf` is created on first run. The menu bar icon has buttons to open and reload it.

It uses Hyprland syntax (`$vars`, `bind = MODS, key, dispatcher, args`, `general { }` blocks) with Amethyst's options (`layouts`, `window-margin-size`, `screen-padding-*`, `mouse-follows-focus`, `focus-follows-mouse`, `mouse-swaps-windows`, `mouse-resizes-windows`, `floating`, `floating-is-blacklist`, `float-small-windows`, `new-windows-to-main`, `enables-layout-hud`, `ignore-menu-bar`, `window-resize-step`, …). It also adds `animate`, `animation-duration`, `animation-curve` (`ease-out`, `ease-in-out`, `linear`, `spring`, `bounce`, `overshoot` or `cubic-bezier(x1, y1, x2, y2)`) and `animation-bounce` (0–1, how lively springs, bounces and overshoot are).

The default `$mod` is **Option**, so your app shortcuts like ⌘Q and ⌘C keep working. Set `$mod = SUPER` to use Command like Hyprland does.

### Window mode (submaps)

Binds can live in a mode, like Hyprland's submaps. A global shortcut enters the mode, and single keys work inside it. Outside the mode, those keys reach your apps untouched.

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
- In Settings → Shortcuts, switch between **Global** and **Window mode** to edit each set.

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

Ouch has its own workspaces, like Hyprland and AeroSpace:

- Each display shows one workspace. A workspace remembers its layout and its last focused window.
- Windows on hidden workspaces are parked just off-screen in a corner of their display; macOS won't let a window go fully off-screen.
- If you ⌘-Tab or click the Dock to a window on a hidden workspace, Ouch switches to that workspace.
- The menu bar shows ① ② ❸; the filled number is the workspace you're on. Click it to pick a workspace.
- `workspace` accepts `N`, `name:foo`, `previous`, `+1` / `-1` and `e+1` / `e-1` (the next workspace that has windows). `movetoworkspace` follows the window; `movetoworkspacesilent` doesn't.
- Workspaces live on one **home Desktop** per display: the macOS Desktop you were on at first launch, or the one chosen in Settings → Windows → Advanced. Other Desktops tile normally, and ⌘1–0 from one of them goes home first. This setup works best with a single macOS Desktop.
- When Ouch quits, crashes or is killed, every parked window is put back on screen, and assignments are saved for the next launch.
- To use macOS Spaces instead, set `virtual-workspaces = false`. Space switching then uses "Switch to Desktop N" when it's on, and otherwise steps with Ctrl-←/→.
- `stay-on-workspace-after-close = true` (default) keeps you on your current workspace when you close a window, instead of jumping to the workspace of whichever window macOS refocuses. Also under Settings → Windows → Advanced.

On the Ouch home Desktop, **Bring Window Here** in the menu bar lists standard, non-minimized windows from other macOS Desktops. Select one to import it into the current Ouch workspace without switching Desktops or moving the pointer. The imported window arrives in its tile, and the other tiles slide to make room. `movetoworkspace` and `movetoworkspacesilent` can also move a focused native-Desktop window directly to an Ouch workspace. Native fullscreen windows and hidden apps are excluded.

A plain click on a running app in the **Dock** also brings its preferred window from a native Desktop into the Ouch workspace on the Dock's display and focuses it. Ouch handles that click before the Dock can switch Desktops. Apps already on an Ouch home Desktop, minimized/fullscreen windows, hidden apps, modified clicks, dragging and long presses keep the Dock's usual behavior.

This uses an undocumented bridged WindowServer operation adapted from [WhichSpace](https://github.com/gechr/WhichSpace). Tested on macOS 27.0.1 with SIP enabled: five imports took 5–7 ms, with no active Desktop change. Older macOS builds may refuse it; Ouch verifies actual Space membership before committing an assignment and reports failure without switching Desktops. See [the investigation and standalone probe](design/native-space-import.md).

### Dispatchers

| Dispatcher | Args |
|---|---|
| `movefocus` | `l r u d` |
| `movewindow` / `swapwindow` | `l r u d`, or `mon:l`, `mon:+1`, `mon:0` |
| `cyclenext` / `swapnext` | *(none)* or `prev` |
| `layoutmsg` | `swapwithmaster`, `focusmaster`, `addmaster`, `removemaster`, `mfact ±0.05`, `orientationnext`/`prev` |
| `splitratio` | `+0.05`, `-0.05`, `exact 0.6` |
| `togglefloating`, `fullscreen`, `killactive`, `exit` | |
| `nativefullscreen` | macOS Full Screen (the green button) on and off |
| `exec` | shell command |
| `focusmonitor` | `l r u d`, `+1`, `-1`, index |
| `workspace` / `movetoworkspace` | `1`–`10` (requires macOS's "Switch to Desktop N" shortcuts on Ctrl+N) |
| `cyclelayout` | `next` / `prev` |
| `layout` | layout name, e.g. `bsp` |
| `toggletiling`, `retile`, `reload` | |
| `sethomespace` | makes the current macOS Desktop the home for workspaces |

## Tiling fixes compared to Amethyst

- Frames are set size → position → size, so windows moving to a smaller or offset display aren't clamped into the wrong slot.
- `AXEnhancedUserInterface`, which Magnet, Rectangle, Grammarly and VoiceOver turn on, is switched off while windows move. Those apps otherwise ignore new frames or animate them wrongly.
- Every frame is checked after it settles and retried once. A window with a minimum size larger than its slot is kept on screen, aligned with its slot.
- Windows that an app moves itself after opening get a second pass and are snapped back. Snap-back gives up after three tries so it can't loop.
- Slot edges are rounded independently, so there are never 1px gaps or overlaps between windows.
- Windows on the current space come from the CoreGraphics window list instead of AX alone. Windows on other spaces and minimized windows no longer leave holes in the layout.
- Windows that can't be resized float automatically instead of breaking the layout.

## Menu bar menu

Click the menu bar item for Ouch's menu. Type to search every command (↩ runs the first match), or use the four toggles at the top: Tiling, Float Window, Fullscreen and Retile. Below them are your workspaces, then **Layout**, **Window** and **Configs** submenus. ↑↓ move, → opens a submenu, ← and Esc go back. Rows show the window-mode key for each command.

## Settings window

Open it from the menu bar menu with **Settings…** (⌘,). Changes save and apply automatically, and **Undo All Changes** goes back to how things were when you opened the window. The search field (⌘K) finds every setting, including ones tucked under a pane's **Advanced** section, and takes you to it.

- **General:** permission and keybind status, open at login, tiling, the main modifier, updates. Advanced: beta releases. Reset everything is at the bottom.
- **Layout:** the layout of each display, the layouts in the cycle, gaps and padding with a live preview, the layout HUD. Advanced: smart gaps, per-side padding, the built-in display, the menu bar, the main pane resize step.
- **Windows:** focus follows mouse, mouse follows focus, drag to swap or resize, floating apps, Ouch workspaces. Advanced: new windows, small windows, bundle IDs, the home Desktop.
- **Motion:** style presets (None, Snappy, Smooth, Relaxed, Springy, Wobbly, Bouncy, Playful), a preview and duration. Advanced: curve and bounciness.
- **Shortcuts:** grouped by category. Click a shortcut, then press the new keys to record it. Invalid shortcuts are flagged in red; ones that replace a standard app shortcut like ⌘Q are flagged in orange. The keyboard button opens the Shortcut Map. Gaming (WASD) and Restore Defaults are at the bottom.

Detailed logging is a launch argument now: `open build/ouch.app --args --verbose`. The old `debug-logging` key still works.

## Command line

```sh
build/ouch.app/Contents/MacOS/ouch dispatch movefocus l
build/ouch.app/Contents/MacOS/ouch dump      # writes tiling state to ~/Library/Logs/ouch.log
build/ouch.app/Contents/MacOS/ouch reload
build/ouch.app/Contents/MacOS/ouch docs      # prints the folder of bundled agent docs
```

`exec` only works from keyboard shortcuts, not from the command line.

## Rebuilding

The app is ad-hoc signed, so every rebuild cancels its Accessibility permission. Ouch shows a ⚠️ in the menu bar and opens Settings. Click **Reset Permission** there, then turn Ouch on again.

## For AI agents

Condensed, task-oriented docs for agents operating or configuring Ouch live in [Resources/AgentDocs/](Resources/AgentDocs/README.md).
