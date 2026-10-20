# Workspaces and displays

With `virtual-workspaces = true`, Ouch workspaces use normal macOS Desktops. Ouch controls switching, window transfers, and overview. It does not park hidden windows at a screen edge.

- Each workspace has one native Desktop. Its name, layout, and last focused window persist between switches.
- Existing normal Desktops become numbered workspaces. Names stay attached to Desktop IDs when macOS reorders them.
- Ctrl+1 through Ctrl+9 selects workspace 1 through 9. Ctrl+0 selects workspace 10. Ctrl+Left and Ctrl+Right select the adjacent workspace on the current display.
- Explicit binds take priority over these defaults. Ouch does not change macOS shortcut preferences.
- Selecting a workspace that does not exist creates a Desktop through Mission Control. Mission Control opens briefly and then closes.
- The menu bar shows the current workspace. Click it to select another workspace.
- Native full screen windows remain on their own Desktops and appear separately in overview.
- Quitting Ouch leaves windows on their native Desktops. A separate recovery process restores Desktop transforms if Ouch stops during a switch.
- `virtual-workspaces = false` leaves Desktop switching to macOS. Ouch continues to tile the active Desktop.
- `stay-on-workspace-after-close = true` keeps you on the current workspace after a window closes.

Ouch uses its configured animation duration and curve to move whole Desktops. A new request replaces the pending destination. An opposite request can reverse motion before the switch commits. Horizontal Desktop gestures use the same controller for progress, reversal, cancellation, and completion.

## Window switcher

The `switcher` dispatcher lists the windows on every workspace Desktop and on full-screen Desktops. It reads them from the shared window-server observation, so opening it does not query the window server. Choosing a window on another workspace uses the same workspace switch and animation as `workspace`, and that window gets focus when the switch settles. Windows on full-screen Desktops, and every Desktop with `virtual-workspaces = false`, use the macOS focus call, which moves to their Desktop.

## Overview

Overview includes normal Desktops, including empty ones, and windows on hidden Desktops. Changes to workspace membership apply when overview closes. New workspaces create native Desktops. Removing a workspace requires a different active Desktop and no remaining native windows on the removed Desktop. macOS can refuse a creation, removal, or window transfer. Ouch reports that failure in a HUD.

## Move a window between Desktops

`movetoworkspace` moves the focused window to the requested Desktop and follows it. `movetoworkspacesilent` moves it while keeping the current Desktop active. A missing destination is created first.

The menu bar's **Bring Window Here** action imports a window from another Desktop. It lists standard windows exposed by Accessibility or previously discovered by Ouch. Hidden apps and native full screen windows are excluded. A plain Dock click can also import an app's preferred window. Modified clicks, dragging, long presses, and minimized or native full screen windows keep normal macOS behavior.

Window transfers use a private bridged operation, tested on macOS 27.0.1 with SIP enabled. If macOS refuses a transfer, Ouch reports the failure. No Dock injection or SIP change is required.

## Tiling behavior

- Windows that cannot resize float automatically. A window larger than its slot stays on screen.
- Hidden Desktop windows and minimized windows do not leave holes in the active layout.
- Ouch prepares the destination layout before Desktop motion begins.
- Ouch verifies window frames after placement. Corrections stop after three attempts.
- Ouch temporarily disables `AXEnhancedUserInterface` while moving windows.
- Ouch's own windows float. The onboarding tour uses a separate practice process.
