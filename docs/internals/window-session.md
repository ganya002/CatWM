# Window session

`Sources/CatWMKit/Session/` saves and opens app windows and knows nothing about CatWM. It has no CatWM types such as `WindowManager`, `WorkspaceModel`, `Layout`, `Theme` or `HUD`, and `Tools/check-style.sh` rejects those names there. `Templates/` builds on it and owns workspaces, Desktops, layouts and frames. `SavedWindow.state` and `.launch` are optional, so an old `templates.json` loads without a migration.

## Save

The AX read has a 2 s budget and a 2.6 s backstop. App state runs only with `template-app-scripting` on, and only after the AX read, so a slow script can't make the AX read time out.

macOS gives each native tab (Terminal, Finder, TextEdit) its own AX window, and only the selected one is on screen. A hidden window with the same frame (within 1 pt) as an on-screen window of the same app counts as a background tab. The adapter saves every tab in the visible window's state, so the hidden windows are dropped. If the visible window gets no state, for example because Automation is off, they stay as windows of their own.

A script returns titles and frames but no `CGWindowID`. `AppStateCapture.attach` pairs scripted and AX windows greedily by cost: the frame distance when the titles match, plus 500 when they don't (allowed only within 24 pt), or 1000 for a title-only match.

## Adapters

Scripted apps (Safari, Chromium browsers, Terminal, iTerm2, Finder) read state with JXA and reopen it with AppleScript or a file. Each script runs in its own `osascript` process, killed at the timeout, so an unresponsive app can't hang CatWM. Code editors (VS Code and its forks, Zed, Xcode) need no Automation. They read the editor's recent-project data read-only, and the window's AX title and document pick the project.

- **Project guess.** `ProjectGuess.pick` narrows the recent list to projects named in the title, then takes the deepest one that contains the open file. Without the title step, a recently opened nested folder would replace the parent project the window has open. Xcode has no readable recent list, so CatWM walks up from the document to the first `.xcworkspace`, `.xcodeproj` or `Package.swift`, at most 12 levels and never past home.
- **Terminal tabs.** Terminal scripting can't create a tab, so a multi-tab window reopens from a temporary window-group file, deleted after 30 s. Tabs get the default profile.
- **Working directory.** `WorkingDirectory` gets a tab's folder without a script. It takes the tty's foreground process group from `sysctl` and that process's current directory from `proc_pidinfo`.
- **Automation.** `AEDeterminePermissionToAutomateTarget` can block on the user, so it runs on a background queue with a timeout that counts as "needs consent". A save may ask, and an open never does. A denied adapter falls through to the next way to open.

## Open

`TemplateRestorer` first discovers a window for each saved window, then applies Desktops, layouts and frames. Tiling owns placement: `registerPlacements` and `placeWindows` reuse the normal backend and `Animator`, and `PlacementHolds` keeps hidden windows waiting until a scan confirms they're visible.

Discovery loops every 0.3 s for up to 15 s. For each request it uses the first way that applies: a `launch.command`, the app adapter, a URL or document, the app's New Window item or ⌘N, and finally a reopen event. Electron apps have no New Window item, and the reopen is the request a Dock click sends, without bringing the app forward. A failed request retries after 0.5 s, up to 3 times. A started command or open never retries, so a slow app doesn't get two windows.

A freshly launched app gets 3 s (0.75 s if it already has a window or a document) to bring back its own windows through macOS Resume before CatWM opens new ones.

`WindowMatch.assign` matches in rounds by score: same window ID and launch date, then same document, then same title, then generic. Within a round, the nearest frame wins, then creation order. An existing window with a different document never matches as generic, even with the same title, so restore opens the saved tabs instead of reusing an unrelated browser window. A scripted window can show a different URL while it loads, so `MatchStability` waits until a generic or title match holds for 0.6 s, up to 2 s. Frame changes don't restart that wait.

## The launch dispatcher

`launch Terminal workspace=2 frame=0,0,50%,100%` reads options from the end of the argument. A word with `=` that isn't `workspace`, `display` or `frame` stays in the target, so URLs with a query work. A pending launch claims the app's next new window for 15 s. The CLI can't run `launch` because the target can be a `.command` file.
