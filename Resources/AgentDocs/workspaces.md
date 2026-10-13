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

## Tiling behaviour worth knowing

- Windows that can't be resized float automatically. Windows with a minimum size larger than their slot stay on screen, aligned to the slot.
- Frames are verified after settling and retried once. Windows moved by their own app get a second pass; snap-back gives up after three tries.
- Windows on other Spaces and minimized windows don't leave holes in the layout.
- `AXEnhancedUserInterface` (turned on by Magnet, Rectangle, Grammarly, VoiceOver) is switched off while windows move.
- Ouch's own windows are never tiled (so the keyboard tour uses a helper process for its practice windows).
