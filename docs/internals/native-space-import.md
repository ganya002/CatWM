# Direct imports from native macOS Desktops

Investigated 2026-10-15 on macOS 27.0.1 (26A434), Apple Silicon, SIP enabled.

CatWM's old `moveFocusedWindow` rejected windows assigned to native Desktops. To import an inactive Desktop's window without visiting that Desktop, the real window must first join the home Desktop in WindowServer. Changing only `workspaceOf` cannot do this.

## Results

A helper process created a disposable window and moved its own window to an inactive normal Desktop. A separate parent process tried to bring it to the active Desktop. No user's windows were touched, no Desktop was activated, and no cursor events were generated.

| Operation | Foreign window result |
| --- | --- |
| `SLSMoveWindowsToManagedSpace` | Membership unchanged |
| `SLSSpaceSetCompatID` + `SLSSetWindowListWorkspace` (Hammerspoon's exact `0x79616265` tag) | Membership unchanged; window-list setter returned 1006 |
| `SLSAddWindowsToSpaces` (remove source only if add succeeds) | Membership unchanged |
| `SLSBridgedMoveWindowsToManagedSpaceOperation` through the asynchronous bridged dispatcher | Membership moved to the target; active Desktop unchanged |

The working implementation comes from [WhichSpace's bridge](https://github.com/gechr/WhichSpace/blob/main/WhichSpace/Classes/WindowSpaceMove.c). `Sources/CatWMKit/Tiling/Spaces/NativeSpaceMove.swift` implements the binding and symbol lookup directly in CatWM. There is no separate module, helper library, or external window-manager dependency. Sparkle remains the sole package dependency. The technique's MIT attribution is retained in the app's Resources. The dispatcher has internal linkage: the resolver checks `dlsym`, then walks SkyLight's loaded Mach-O symbol table with bounds checks. A missing class, initializer, or dispatcher returns unavailable.

Five fresh child windows were imported and silently sent back, checking actual Space membership and active Desktops after each operation. All ten moves passed. Import verification took 7, 5, 6, 7, and 5 ms (median 6 ms). These measure WindowServer membership confirmation, not screen refresh or an application's Accessibility response time.

[Hammerspoon's implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/libspaces.m) explains the older compatibility technique. [A macOS 27 report](https://github.com/Hammerspoon/hammerspoon/issues/3897) also describes its failure. Their return paths must not be treated as proof that a window moved.

## Behavior in CatWM

- Menu → **Bring Window Here** discovers other normal Desktop windows through AX plus CatWM's cached handles. It imports into the workspace currently showing on the home Desktop, without focus, cursor movement, or a Space switch.
- A plain Dock click captures the home workspace on the Dock's display before app activation. `DockWindowPull.swift` consumes the click pair for a running app whose preferred standard window is on a native Desktop, then imports and focuses it. Dragging, holding for 350 ms, releasing outside the icon, or adding modifiers replays the original events to the Dock. Other clicks pass through. No system Dock preference is changed.
- Existing `movetoworkspace` and `movetoworkspacesilent` also import focused native-Desktop windows. Following goes to the home Desktop once; silent movement does not activate it.
- CatWM checks Space membership immediately, then every 4 ms for at most 500 ms. There is no mandatory transition delay. For a visible destination, CatWM also waits for the window to enter the on-screen list. CatWM commits the assignment after both checks pass.
- Refresh does not discover windows with an import in progress as new arrivals. It lays them out in their destination workspace.
- Before the bridged request, CatWM assigns the window to its destination and writes only its tile frame while the window is still on its old Desktop. The window then arrives in its tile. It does not arrive at its old frame on top of the other tiles. After it arrives, the other tiles make room with the configured animation.
- Native imports hold WindowServer display updates during the Space move only, from the bridged request until the window is on screen. This is intended to suppress the reported flash of all windows during an import. It uses `SLSDisableUpdate` / `SLSReenableUpdate`, with overlapping leases and an independent 300 ms watchdog. The Space move alone took 44–61 ms in the app log, so the earlier 120 ms watchdog, which also had to cover the relayout, often released the display too early. The log line `import of … held the display … ms` records each hold. Ordinary CatWM tiling is unchanged. No screen capture is started and no fixed delay is added; if the APIs are unavailable, the import proceeds normally.
- Requests for the same window cannot overlap. Unsupported or refused operations report a HUD failure; there is no automatic visible-switch fallback.
- Native fullscreen, minimized, hidden-app, sticky, and unknown-membership windows are excluded from the menu. An app that does not expose an inactive window through AX needs CatWM to have discovered its AX handle earlier.
- This is an unsupported private API, tested on this OS build. Availability of its symbols alone does not guarantee permission to move a foreign window on other versions.

## Repeat the live probe

Requires two normal macOS Desktops and a logged-in GUI session. It creates only disposable helper windows; it does not require Accessibility or change any system settings. Run from the repository root:

```sh
mkdir -p /tmp/catwm-space-check
cp Tools/SpaceMoveProbe.swift /tmp/catwm-space-check/main.swift
swiftc -module-cache-path /tmp/catwm-space-check/modules \
  Sources/CatWMKit/Tiling/Spaces/NativeSpaceMove.swift Sources/CatWMKit/Tiling/Spaces/WindowServerUpdates.swift \
  /tmp/catwm-space-check/main.swift \
  -o /tmp/catwm-space-check/probe
/tmp/catwm-space-check/probe
```

The probe fails if an import or silent send does not change membership, or if the active Desktop changes. Each child is terminated after its test and has its own ten-second exit timer.

Run `/tmp/catwm-space-check/probe --batch-updates` to require display-update batching during imports. This passed five imports and five silent sends with no recording active, at a 6 ms median import. It verifies API availability, membership and Desktop stability; it cannot prove the physical panel does not flash. That needs a check in the running CatWM app without screen recording.

`Tools/WindowServerUpdatesProbe.swift`, compiled as `main.swift` alongside `Sources/CatWMKit/Tiling/Spaces/WindowServerUpdates.swift`, checks release after overlapping leases, duplicate finish calls, timeout with the main thread blocked, stale leases from an earlier batch, dropped leases, and API failure. Its injected operations do not modify the display.

## Check screen visibility after import

A user recording showed an intermediate layout change before Finder settled into its tile. Code inspection found two possible contributors. Refresh could discover the imported window before the import completed. Also, existing tiles still animated after the display batch ended.

A later revision placed all affected tiles without animation. The current import places only the imported window before the move and animates the other tiles after it arrives. Completion also waits for screen visibility when the destination Desktop is active. Passing live runs measured medians of 23 ms and 53 ms to this completion point. The earlier 6 ms result measured membership alone. This difference does not prove the cause of the physical flash.

Compile the probe with the actual `Spaces.move` wrapper to check visibility at completion:

```sh
cp Tools/SpaceMoveProbe.swift /tmp/catwm-space-check/main.swift
swiftc -D CATWM_ARRIVAL_PROBE -module-cache-path /tmp/catwm-space-check/modules \
  Sources/CatWMKit/Tiling/Spaces/NativeSpaceMove.swift Sources/CatWMKit/Tiling/Spaces/WindowServerUpdates.swift \
  Sources/CatWMKit/Tiling/Access/PrivateSymbols.swift Sources/CatWMKit/Tiling/Access/Spaces.swift /tmp/catwm-space-check/main.swift \
  -o /tmp/catwm-space-check/arrival-probe
/tmp/catwm-space-check/arrival-probe --batch-updates
```

This mode checks that completion occurs after screen visibility. It also checks that the active Desktop remains unchanged. The parent process does not initialize `NSApplication` during this check.

## Check Dock click handling

`Tools/DockClickProbe.swift` checks click consumption, modifier passthrough, drag replay ordering, long presses, outside releases, unrelated clicks and the Dock edge bands that gate the Accessibility hit test. It installs no event tap and captures replay events instead of posting them. Compile it as `main.swift` alongside `Sources/CatWMKit/Tiling/Input/DockWindowPull.swift`:

```sh
mkdir -p /tmp/catwm-dock-check
cp Tools/DockClickProbe.swift /tmp/catwm-dock-check/main.swift
swiftc -module-cache-path /tmp/catwm-dock-check/modules \
  Sources/CatWMKit/Tiling/Input/DockWindowPull.swift /tmp/catwm-dock-check/main.swift \
  -o /tmp/catwm-dock-check/probe
/tmp/catwm-dock-check/probe
```

The isolated click checks and app build pass. End-to-end clicking a real Dock icon has not been verified: the standalone inspection executable has no Accessibility grant. The running CatWM app needs its existing Accessibility permission for hit-testing Dock icons and querying their windows.
