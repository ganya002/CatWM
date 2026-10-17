# Workspaces and displays

Ouch has its own workspaces (like Hyprland/AeroSpace) by default (`virtual-workspaces = true`).

- Each display shows one workspace. A workspace remembers its layout and last focused window.
- Hidden workspaces' windows are **parked** just off-screen in a corner of their display (macOS won't allow fully off-screen).
- ⌘-Tab or a Dock click to a window on a hidden workspace switches to that workspace.
- The menu bar shows ① ② ❸; the filled number is the current one. Click to pick.
- Workspaces live on one **home Desktop** per display: the macOS Desktop at first launch, or the one chosen in Settings → Windows → Advanced (or `sethomespace`). Other Desktops tile normally; ⌘1–0 from one goes home first. Works best with a single macOS Desktop.
- When Ouch quits, crashes or is killed, parked windows are restored on-screen (SIGTERM, SIGINT, SIGHUP are handled). Assignments are saved for next launch.
- `virtual-workspaces = false` uses macOS Spaces instead (see [dispatchers.md](dispatchers.md) for the shortcut requirement).
- `stay-on-workspace-after-close = true` keeps you where you are after closing a window.

## Import a window from a macOS Desktop

On the home Desktop, open the menu bar menu → **Bring Window Here** and select a window. It joins the current Ouch workspace without activating the source Desktop. The menu lists standard, non-minimized windows exposed by Accessibility or previously discovered by Ouch. Hidden apps and native fullscreen windows are excluded.

A plain Dock click on a running app also imports and focuses its preferred native-Desktop window into the Ouch workspace on the Dock's display. Ouch intercepts the click before macOS switches Desktops. Modified clicks, dragging, long presses, hidden apps, minimized/fullscreen windows and apps whose preferred window is already on an Ouch home Desktop keep their usual behavior.

`movetoworkspace` / `movetoworkspacesilent` also accept a focused window on a native Desktop. The silent command leaves that Desktop active. The following command goes to the destination home Desktop once.

The direct import uses a private bridged operation, verified on macOS 27.0.1 with SIP enabled. If macOS refuses it, the assignment is not changed and a HUD reports failure. Ouch does not fall back to visiting the source Desktop. See `docs/native-space-import.md` in the source repository for the standalone GUI-session probe.

## Tiling behaviour worth knowing

- Windows that can't be resized float automatically. Windows with a minimum size larger than their slot stay on screen, aligned to the slot.
- Frames are verified after settling and retried once. Windows moved by their own app get a second pass; snap-back gives up after three tries.
- Windows on other Spaces and minimized windows don't leave holes in the layout.
- `AXEnhancedUserInterface` (turned on by Magnet, Rectangle, Grammarly, VoiceOver) is switched off while windows move.
- Ouch's own windows are never tiled (so the keyboard tour uses a helper process for its practice windows).
