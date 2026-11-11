# Agent display

An agent display is a private virtual display that one owner object holds for an agent. The agent's apps open their windows on it, so they never take the user's focus, Desktop or cursor, and the user's CatWM never tiles them. `AgentDisplay` (`Sources/CatWMKit/Tiling/Spaces/`) is the engine part. The `agent.*` commands and the Python `Sandbox` drive it.

## Decisions

**A virtual display, not a Desktop.** A window on a Desktop that is not active is mostly out of reach: AX hides the windows of other Desktops from an app that has not shown them, so reads and writes fail until the Desktop is visited, and visiting it moves the user (`native-space-import.md`). A virtual display is always active, so its windows stay readable, `ScreenCaptureKit` captures them and `CGEvent.postToPid` reaches them. The cost is a private API (`CGVirtualDisplay`), resolved at runtime like the other private symbols. A missing class makes the init fail, and the owner reports unavailable.

**The display is hidden from the user's CatWM by its identity.** `Screen.all()` and `NSScreen.userScreens` drop a display whose vendor and model number are the agent display's. Every CatWM process makes the same test from the display ID alone. A claim file could not do this, because it would have to exist before the display does, and one missed scan would create a workspace and a Desktop for it. The windows are hidden separately, by pid (next decision), so the display ID is the only thing the screen code needs.

**The app's pid is claimed, not placed.** `claimLaunch` and `place` wait for a window to reach the manager's refresh, and a claimed pid never does: that is the point of the claim. So the agent launch skips them and reuses the parts below them. `Launcher.start` returns the launched app (and takes `activates: false`), and `ScopeClaims` carries the pid to every CatWM, including the owner's own. Each display writes its own `instances/agent-<id>/scope`, so displays don't overwrite each other, and the file goes with the display. A killed owner is caught by the existing owner-pid watch.

**An app that already runs is refused.** The claim moves every window of the pid, so claiming an app the user is working in would carry their documents away.

**Moves follow an AX observer, with a retry.** `kAXWindowCreated` finds every later window, and each window also reports `kAXMoved`. Some apps (TextEdit) create a window inside the display and then apply their saved frame, so a single sweep at creation leaves the window on the user's display. A sweep polls for `settle` and a move notification starts it again. A new process refuses the registration until its launch has finished, so the observer retries every 10 ms for as long as the process lives (`kill`, because `NSRunningApplication` can lag behind a launch). A window that exists when the registration succeeds is swept at once.

**A lease hides the move, not the launch.** `WindowServerUpdates` holds the display updates from the first move until the window reports bounds on the agent display, then lets go before the 300 ms watchdog. The alternative is to hold the lease from the launch request. It would freeze the user's screen for the whole launch, which is longer than the watchdog and varies from app to app, to hide a window whose creation time nobody knows. The lease starts when the window is first known, so a window can still appear on the user's display before the notification arrives. The server lists it there, and no measurement without a screen recording says whether the panel shows it.

**Closing the owner does not quit the apps.** Quitting could lose unsaved documents. macOS moves the windows of a removed display to the user's display, so an owner should quit its apps before it lets go.

## Commands

**The display belongs to the socket connection that opened it.** A test that crashes or gets `kill -9` must not leave a display and running apps behind, and a close command cannot cover that. The kernel closes the socket whatever happens to the client, so `ControlServer`'s close hook (read on the background queue, then run on main after the lines already read) quits the apps and then releases the display. The alternative is an owner pid watch like `ScopeClaims`. It needs polling or a second watcher and still has to map a pid to a display, while the connection already is that mapping. The cost is that the CLI cannot keep a display across calls, because each call is a connection. Only a library can.

**A connection has one display, and `agent.close` is the same path as the hook.** Both take the display out of `AgentSessions` first, so a second close finds nothing. `makeVirtual` waits for the display on the main run loop, which also runs the close hook and other commands, so `open` marks the connection as opening. A close during that wait makes `open` release the display it just made instead of storing it, and a second `open` is refused.

**Quitting waits, then forces.** The claim stays until every app has exited, so the user's CatWM never sees a half-quit app as a normal window. After a grace period an app that still lives is force-terminated, because a test sandbox holds no documents worth a "save changes" dialog that nobody can answer.

**Buttons are pressed by title.** Some apps open with a panel and no document (TextEdit shows an Open panel). Launch arguments could skip it, but an argument list is the same as running arbitrary code for apps that take one. `agent.press` presses a button of a window through AX, with no focus, and it needs no event routing to an inactive app. Posted key events did not reach the Open panel of an inactive TextEdit.

**Window IDs, not workspaces.** The user's CatWM ignores these windows, so `windows` and `window.added` never show them. `agent.windows` lists the claimed pids' windows that sit on the display, and every input command takes one of those IDs. A window that is not on the display is refused, so these commands cannot type into the user's apps.

**Text goes in through AX first.** `AXValue` set reaches an app that is not frontmost, needs no focus and does not depend on key events being routed to a key window. `CGEvent.postToPid` is the fallback for views that expose no settable text field. It uses a private event source, so it does not touch the combined modifier state or the cursor. An AX set appends to the field, so `text` reads back exactly what was typed.

**A screenshot is one frame on demand.** `SCScreenshotManager` captures a single window, so no stream runs between calls and the window may be on any display. It needs Screen Recording, like the template thumbnails.

**The commands are public, and `launch` and `exec` stay keybindOnly.** `exec` and `launch` run what a string says: a path, a URL or a shell command. `agent.launch` takes only a bundle ID that the system resolves to an installed app, refuses a running one, opens it without focus and quits it when the connection closes. The same process can already run `open -b`. The input commands reach only pids that this connection launched. So the commands add no way to run code that the user's account could not already run. A scoped instance allows them, because they leave its scope alone: the display is new, and the apps and the events are the connection's own.

**A deferred command replies when it is done.** `launch`, `screenshot` and `close` wait for an app or the window server, and the main queue must not block. They reply from a task, so a client that sends a second request before the first reply can get the replies out of order. The request IDs tie them together, and the libraries send one request at a time.
