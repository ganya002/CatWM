# Imports from native macOS Desktops

**Bring Window Here**, a Dock click and `movetoworkspace` can pull a window from an inactive Desktop without visiting it. Changing `workspaceOf` isn't enough: the real window has to join the home Desktop in WindowServer, and only one private SkyLight path does that for another app's window.

## Which API works

Tested on macOS 27.0.1 (26A434), Apple Silicon, SIP on. A helper process moved its own window to an inactive Desktop, and a separate parent tried to bring it back:

| Operation | Result for another app's window |
| --- | --- |
| `SLSMoveWindowsToManagedSpace` | Membership unchanged |
| `SLSSpaceSetCompatID` + `SLSSetWindowListWorkspace` (Hammerspoon's `0x79616265` tag) | Membership unchanged, setter returned 1006 |
| `SLSAddWindowsToSpaces` | Membership unchanged |
| `SLSBridgedMoveWindowsToManagedSpaceOperation` through the bridged dispatcher | Moved, active Desktop unchanged |

The working path comes from [WhichSpace](https://github.com/gechr/WhichSpace/blob/main/WhichSpace/Classes/WindowSpaceMove.c), under MIT, with attribution in Resources. `NativeSpaceMove.swift` binds it directly, with no helper library. The dispatcher has internal linkage, so the resolver tries `dlsym` and then walks SkyLight's loaded Mach-O symbol table with bounds checks. A missing piece reports unavailable. [Hammerspoon's older technique](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/libspaces.m) [fails on macOS 27](https://github.com/Hammerspoon/hammerspoon/issues/3897). These APIs return success without moving the window, so CatWM checks membership itself and never trusts a return code.

## How an import runs

- CatWM assigns the window to its destination and writes its tile frame while it's still on the old Desktop. It arrives in its tile instead of on top of the other tiles, and they make room afterwards with the normal animation. Refresh doesn't treat an importing window as a new arrival.
- It checks Space membership at once, then every 4 ms for up to 500 ms, with no fixed delay. For a visible destination, it also waits for the window to reach the on-screen list.
- `SLSDisableUpdate` holds display updates from the bridged request until the window is on screen, to hide the flash of all windows. Leases can overlap, and a 300 ms watchdog releases them. The move alone took 44–61 ms in the log, so an earlier 120 ms watchdog that also covered the relayout often let go too early.
- A Dock click is captured before the app activates. `DockWindowPull` consumes the click pair when the app's preferred window is on another Desktop. A drag, a 350 ms hold, a release outside the icon or a modifier replays the events to the Dock.
- Requests for one window can't overlap. A refused move reports in the HUD, with no fallback to a visible Desktop switch.
- Native full-screen, minimized, hidden-app, sticky and unknown-membership windows are excluded. An app that hides inactive windows from AX needs CatWM to have seen the AX handle earlier.

Imports confirm membership in about 6 ms and screen visibility in 23–53 ms. That doesn't prove the physical panel doesn't flash, so check that in the running app without screen recording.

## Probes

`Tools/SpaceMoveProbe.swift` moves disposable helper windows and fails if membership doesn't change or the active Desktop does. It needs two normal Desktops. Compile it as `main.swift` with `NativeSpaceMove.swift` and `WindowServerUpdates.swift`, and run it with `--batch-updates` to require update batching. Add `-D CATWM_ARRIVAL_PROBE` with `PrivateSymbols.swift` and `Spaces.swift` to check that completion waits for screen visibility. `WindowServerUpdatesProbe.swift` tests the lease logic, and `DockClickProbe.swift` tests click consumption and replay without an event tap. A real Dock click hasn't been verified end to end.
