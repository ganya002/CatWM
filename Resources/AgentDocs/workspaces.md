# Workspaces and displays

With `virtual-workspaces = true`, CatWM workspaces use normal macOS Desktops. CatWM controls switching, window transfers, and overview. It does not park hidden windows at a screen edge.

- Each workspace has one native Desktop. Its name, its columns, and its last focused window persist between switches.
- Existing normal Desktops become numbered workspaces. Names stay attached to Desktop IDs when macOS reorders them.
- Each display has its own Desktops. By default, workspace numbers are unique across all displays. A workspace on another display opens on that display, and keyboard focus goes to that display.
- With `workspaces-per-display = true`, workspace N is the Nth macOS Desktop on that display, counted from the left in Mission Control. `workspace 2` and `movetoworkspace 2` use the second Desktop of the current display. A number above the next free one also creates the Desktops before it, so Desktops never have gaps. When you leave an empty workspace that has no used workspace after it, CatWM removes its Desktop after the switch animation ends, without opening Mission Control. An empty workspace before a used one stays, so workspace numbers never change. If you reorder Desktops in Mission Control, the workspace numbers follow. Overview numbers its columns in the same order, and a column number cannot be typed. Changing this option renumbers all workspaces and clears their names.
- When a display has no window to focus, CatWM moves the cursor to that display. Then the next bind applies to that display.
- A disconnected display keeps its workspace names. They come back when the display connects again.
- Ctrl+1 through Ctrl+9 selects workspace 1 through 9. Ctrl+0 selects workspace 10. Ctrl+Left and Ctrl+Right select the adjacent workspace on the current display.
- Ctrl+Shift with the same keys moves the focused window to that workspace and follows it.
- Explicit binds take priority over these defaults. CatWM does not change macOS shortcut preferences.
- Selecting a workspace that does not exist creates its Desktop on demand, without opening Mission Control. CatWM does not create or keep spare Desktops.
- When you leave an empty workspace, CatWM removes the workspace and its Desktop. Set `remove-empty-workspaces = false` to keep empty workspaces.
- With empty workspaces removed, `r+1` from the last workspace opens a new workspace if the current one has windows.
- The menu bar shows the current workspace. Click it to select another workspace.
- Native full screen windows remain on their own Desktops and appear separately in overview.
- Quitting CatWM leaves windows on their native Desktops. A separate recovery process restores Desktop transforms if CatWM stops during a switch.
- `virtual-workspaces = false` leaves Desktop switching to macOS. CatWM continues to tile the active Desktop.
- `stay-on-workspace-after-close = true` keeps you on the current workspace after a window closes.

CatWM uses its configured animation duration and curve to move whole Desktops. A new request replaces the pending destination. A request for a different display waits until the current switch is complete. An opposite request can reverse motion before the switch commits. Horizontal Desktop gestures use the same controller for progress, reversal, cancellation, and completion.

## Window switcher

The `switcher` dispatcher lists the windows on every workspace Desktop and on full-screen Desktops. It reads them from the shared window-server observation, so opening it does not query the window server. Choosing a window on another workspace uses the same workspace switch and animation as `workspace`, and that window gets focus when the switch settles. Windows on full-screen Desktops, and every Desktop with `virtual-workspaces = false`, use the macOS focus call, which moves to their Desktop.

## Overview

Overview includes normal Desktops, including empty ones, and windows on hidden Desktops. Changes to workspace membership apply when overview closes. New workspaces create native Desktops. Removing a workspace requires a different active Desktop and no remaining native windows on the removed Desktop. macOS can refuse a creation, removal, or window transfer. CatWM reports that failure in a HUD.

## Move a window between Desktops

`movetoworkspace` moves the focused window to the requested Desktop and follows it. `movetoworkspacesilent` moves it while keeping the current Desktop active. A missing destination is created first.

The menu bar's **Bring Window Here** action imports a window from another Desktop. It lists standard windows exposed by Accessibility or previously discovered by CatWM. Hidden apps and native full screen windows are excluded. A plain Dock click can also import an app's preferred window. Modified clicks, dragging, long presses, and minimized or native full screen windows keep normal macOS behavior.

Window transfers use a private bridged operation, tested on macOS 27.0.1 with SIP enabled. If macOS refuses a transfer, CatWM reports the failure. No Dock injection or SIP change is required.

Desktop creation and removal use the same bridge. CatWM checks the native Desktop list before it completes either action. A new Desktop is placed on the requested display before the workspace switch starts. If macOS does not provide these operations, CatWM reports the failure.

## Tiling behavior

- Windows that cannot resize float automatically. A window larger than its slot stays on screen.
- Hidden Desktop windows and minimized windows do not leave holes in the columns.
- CatWM prepares the destination columns before Desktop motion begins.
- CatWM verifies window frames after placement. Corrections stop after three attempts.
- CatWM temporarily disables `AXEnhancedUserInterface` while moving windows.
- CatWM's own windows float. The onboarding tour uses a separate practice process.
