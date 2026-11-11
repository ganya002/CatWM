# Tiling observations

Window-server reads run on the main thread. SkyLight window reads wait for WindowServer to apply this process's last Core Animation transaction, and they hold a process-wide lock while they wait. A read on another thread blocks the main thread's next commit until a 500 ms timeout ends the wait. The running-app list and scope claims still load on a background queue first, and the scan captures app metadata so a command doesn't enumerate running apps again.

## AX reads

The scanner reads AX on one serial queue per app, with separate queues for focus reads, focus writes, scans and placement writes. One hung app must not stall the others, so a busy app has at most one scan in flight, and the scan deadline lets refresh go ahead with the apps that answered. The main thread accepts each snapshot once, and a frame revision stops a late observation from replacing a newer placement. App termination invalidates pending results.

An AX timeout doesn't prove that a window closed. Only an invalid AX element marks a known window as gone.

Frame notifications share one pending read per window. Mouse release asks for a final read before a resize or swap applies. Focus reads carry a generation, so an earlier request's result is rejected. Commands wait for a focus report after activation and keep their order, and the intended window stays pending until the focus write completes and a fresh observation confirms it. A focus result with no window ID, or a sheet with no parent, completes the report with no window instead of retrying forever.

## Reconciliation

`WorkspaceReconciliation` takes display facts, cached frames and the workspace model, and returns a new model, the visible windows and the windows to park. It makes no AX calls, so a test can replay an observation. Pending destinations let a quick workspace switch cancel a park before its write lands. Parking changes position only, because the resize check could clamp a parked window to the visible screen. Quit waits for restoring writes, with a 2 s limit per unresponsive app.

A few explicit actions still read AX for the selected window: native full screen, close, Desktop import, Dock import and the grab diagnostic. They're outside refresh, workspace staging and focus navigation (issue #135).

Verbose logs time `scan`, `refresh`, `reconcile`, `workspace` and `stage-home`, and flag main-thread groups over 16.7 ms. Scan durations include AX time on the app queue, so they don't measure a main-thread stall.

The reconcile step reads the Desktop list through `Spaces.recentList`, which reuses the parsed list of a read up to 100 ms old. One action runs about three refreshes in a row (the dispatch, then two scan-and-refresh rounds), and the window server round trip was a large share of the two that change nothing. We rejected invalidating on `activeSpaceDidChangeNotification` because adding or removing a Desktop in Mission Control sends nothing when the current Desktop stays put. The age limit stays under the 0.15 s delay of the refresh that a Desktop change schedules, so that refresh always reads a fresh list.
