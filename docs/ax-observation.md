# Tiling observations

Window-server observations run on a background queue. They capture visible windows and Desktop membership. Refresh and workspace staging use the last observation. The scan also captures app metadata, so a command does not enumerate running apps again.

The scanner reads AX attributes on one serial queue per app. A scan returns window frames, titles, resize capability, minimized state and full-screen state. The main thread accepts each snapshot once. A frame revision prevents a delayed observation from replacing a newer placement.

A busy app has at most one scan in progress. The scan deadline permits refresh to use results from responsive apps. App termination invalidates pending results. An AX timeout does not prove that a window closed. Only an invalid AX element marks a known window as gone.

Frame notifications request background reads. Repeated notifications share one pending read per window. Mouse release requests a final background read before the manager applies a resize or a swap. Focus notifications update the cached focus ID. App activation requests a background focus read. A generation check rejects results from an earlier focus request.

`WorkspaceReconciliation` accepts display facts, cached frames and the workspace model. It returns a new model, visible windows and windows to park. It performs no AX calls. Tests can replay the same observation. The manager applies the result through the per-app AX writers. Pending destinations let a quick workspace switch cancel a park before the write completes.

Parking changes position only. It does not run the resize verification that can clamp a window to the visible screen. Focus writes also use an AX writer. Startup prepares the HUD and focus sink before the first workspace switch. Status updates share one pending main-queue callback. Workspace HUD updates follow placement and reject an obsolete workspace. Termination waits for restoration writes, with a two-second limit for an app that does not respond.

## Direct actions

Some explicit actions still read AX state for the selected window. These include native full-screen, close, Desktop import, Dock import and the grab diagnostic. Desktop import also reads candidate windows while the user selects a window. These paths are separate from refresh, workspace staging and focus navigation. `dump` reads actual AX frames for diagnostics.

The repository prohibits source comments. This document records the direct-action exceptions required by issue #135.

## Timing and verification

Verbose logs include `scan`, `refresh`, `reconcile`, `workspace`, `stage-home` and command durations. Main-thread groups also log when they exceed 16.7 ms. Scan durations include AX time on the app queue. They do not measure a main-thread stall.

For visual verification, run:

```sh
./build.sh --dev && open build/ouch.app
```

Check these cases:

1. Open at least 50 windows quickly. Check that Ouch remains responsive.
2. Switch workspaces repeatedly while one app does not respond. Check floating windows and tiled windows.
3. Restore the busy app. Check that its delayed results do not replace newer placements.
4. Drag and resize a floating window. Check focus navigation and monitor moves.
5. Close the focused window. Check that focus returns to the most recent window in that workspace.
6. Quit Ouch with hidden workspaces. Check that parked windows return to the screen.

Run `swift test` for snapshot revision checks, a blocked-app scan with 50 responsive windows, scan invalidation and workspace reconciliation replay.

Local check on 2026-10-17 used a debug build with verbose logging. A temporary AppKit app created 50 windows quickly. Ouch managed 54 windows in total. With the test app suspended by `SIGSTOP`, six workspace command handlers took 5.3–12.5 ms. Refresh took 1.1–4.8 ms during those switches. Ouch remained running. These measurements describe that run. They are not a worst-case guarantee. The test app and its temporary workspace data were removed after the check.

After merging main, validation passed 164 tests with `swift test --no-parallel`. Parallel runs intermittently failed the existing `staleScreenshotAfterUpdateDoesNotReplaceNewerWindows` test. IPC Quit completed in 157 ms after the termination callback fix, and Ouch restarted successfully.
