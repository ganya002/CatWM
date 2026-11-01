# Window session

`Sources/CatWM/Session/` saves and opens app windows. It does not know about CatWM workspaces, layouts or Desktops. It has no CatWM types, such as `WindowManager`, `WorkspaceModel`, `Layout`, `Theme` or `HUD`, and `Tools/check-style.sh` rejects these names in it. The code in `Sources/CatWM/Templates/` uses `Session/` and changes the CatWM state.

## Folder map

```mermaid
flowchart TB
    subgraph App["Templates/ and Tiling/Manager/"]
        direction LR
        Library["TemplateLibrary"]
        Capture["WindowManager+captureTemplate<br/>TemplateCaptureAssembler"]
        Restorer["TemplateRestorer<br/>+apply, +pull"]
        LaunchCmd["WindowManager+launch"]
    end

    subgraph WS["Session/"]
        direction LR
        Cap["Capture/<br/>WindowCapture, CaptureSlot"]
        Apps["Apps/<br/>AppStateCapture, AppAdapters,<br/>AppScript, Automation"]
        Res["Restore/<br/>WindowMatch, MatchStability,<br/>RestoreScheduler, RestoreAX"]
        Lch["Launch/<br/>Launcher, LaunchRequest"]
        Model["Model/<br/>SavedWindow, AppState, LaunchSpec"]
        AX["AX/<br/>AXRead"]
    end

    Library --> Capture
    Library --> Restorer
    Capture --> Cap
    Capture -->|"template-app-scripting is on"| Apps
    Restorer --> Res
    Restorer --> Apps
    Restorer --> Lch
    LaunchCmd --> Lch
    Cap --> AX
    Res --> AX
    Apps --> Lch
    Capture --> Model
    Restorer --> Model
```

## Saved data

`WorkspaceTemplate` stays in the app. Its `SavedWindow` is the `Session/` type. The `state` and `launch` fields are optional, so an old `templates.json` file loads without a change.

```mermaid
classDiagram
    class WorkspaceTemplate {
        UUID id
        String name
        Bool tilingEnabled
        Display[] displays
        SavedWindow[] windows
        Data screenshot
    }
    class SavedWindow {
        UUID id
        String bundleID
        String appName
        String title
        String document
        String display
        CGRect frame
        Bool floating
        Bool minimized
        Bool fullscreen
        Bool zoomed
        Bool focused
        CGWindowID windowID
        Date launchDate
        AppState state
        LaunchSpec launch
    }
    class AppState {
        String[] tabs
        Int selected
        current() String
    }
    class LaunchSpec {
        String url
        String[] arguments
        String command
    }
    WorkspaceTemplate "1" *-- "many" SavedWindow
    SavedWindow "1" o-- "0..1" AppState
    SavedWindow "1" o-- "0..1" LaunchSpec
```

`AppState.tabs` holds one URL for each tab. A browser tab is an `http` or `https` URL. A Terminal tab, an iTerm2 tab or a Finder tab is a `file` URL of a folder. A code editor window has one `file` URL: its project folder, `.code-workspace` file, Xcode project or `Package.swift`.

## Save a template

The AX read has a budget of 2 seconds, with a backstop of 2.6 seconds. The app state step runs only when `template-app-scripting` is on. It runs after the AX read, so it cannot make the AX read time out.

```mermaid
sequenceDiagram
    autonumber
    participant UI as Cursor menu or Settings
    participant WM as WindowManager
    participant Slot as CaptureSlot
    participant WC as WindowCapture
    participant AS as TemplateCaptureAssembler
    participant SC as AppStateCapture
    participant AU as Automation
    participant AD as AppAdapter

    UI->>WM: captureTemplate()
    WM->>WM: makeRequest() reads displays, layouts, workspaces
    WM->>Slot: run(within: 2.6 s)
    Slot->>WC: collect(apps, budget: 2 s) on a background task
    WC-->>Slot: WindowBatch
    Slot-->>WM: finished(batch), timedOut, busy or cancelled
    WM->>AS: make(facts, batch)
    AS-->>WM: WorkspaceTemplate
    alt template-app-scripting is on
        WM->>WM: WindowTabs.background(windows, onScreen) finds hidden tab windows
        WM->>SC: capture(visible windows, consentWait: 30 s, scriptTimeout: 3 s)
        par one task for each app with an adapter
            opt captureNeedsAutomation
                SC->>AU: access(bundleID, ask: true)
                AU-->>SC: granted, denied, needsConsent or notRunning
            end
            SC->>AD: capture(bundleID, windows)
            AD-->>SC: ScriptedWindow list
            SC->>SC: attach(scripted, to: windows)
        end
        SC-->>WM: AppState for each window ID
        WM->>WM: drop hidden tab windows whose visible window got a state
        WM->>WM: set SavedWindow.state
    end
    WM-->>UI: WorkspaceTemplate
```

### Background tabs

macOS gives each native tab (Terminal, Finder, TextEdit) its own AX window. Only the selected tab is on screen. A hidden window of an app with an adapter is a background tab when an on-screen window of the same app has the same frame (within 1 point). The adapter saves all tabs in the state of the visible window, so the hidden tab windows are removed from the template. If the visible window gets no state, for example because Automation is off, CatWM keeps the hidden windows.

```mermaid
flowchart LR
    W["Windows of apps with an adapter"] --> On{"On screen?"}
    On -- Yes --> Keep["visible window"]
    On -- No --> Same{"An on-screen window of the same app has the same frame?"}
    Same -- No --> Keep2["keep as its own window"]
    Same -- Yes --> Tab["background tab of that window"]
    Tab --> Got{"Visible window got an AppState?"}
    Got -- Yes --> Drop["remove from the template"]
    Got -- No --> Keep2
```

Finder scripting lists each tab as a Finder window. `WindowTabs.merged` joins the scripted windows that have the same frame into one state, in front-to-back order, so the front tab is the selected tab.

### Pair a scripted window with an AX window

A script gives a title and a frame for each window. It does not give a `CGWindowID`. `AppStateCapture.attach` finds the pairs. It sorts all pairs by cost and takes the lowest cost first. Each window and each scripted window is used one time.

```mermaid
flowchart TD
    Start["Scripted window and AX window"] --> HasFrame{"Script gave a frame?"}
    HasFrame -- No --> TitleOnly{"Same title?"}
    TitleOnly -- Yes --> C1000["cost = 1000"]
    TitleOnly -- No --> Reject["no pair"]
    HasFrame -- Yes --> Distance["distance = sum of x, y, width and height differences"]
    Distance --> Titled{"Same title?"}
    Titled -- Yes --> CD["cost = distance"]
    Titled -- No --> Near{"distance 24 or less?"}
    Near -- Yes --> C500["cost = distance + 500"]
    Near -- No --> Reject
```

## App adapters

An adapter reads the state of one app and opens it again. For scripted apps, JavaScript for Automation (JXA) reads the state and returns JSON, and AppleScript or a file opens it again. The code editor adapters need no script and no Automation: they read the editor's own recent-project data with `SQLiteRead` (read-only), and they get the AX title, frame and document of each window to choose the project. `AppScript` runs each script in an `osascript` process. A timer stops the process at the timeout, so an app that does not respond cannot stop CatWM.

```mermaid
classDiagram
    class AppAdapter {
        <<protocol>>
        Set~String~ bundleIDs
        Bool captureNeedsAutomation
        Bool restoreNeedsAutomation
        capture(bundleID, windows, timeout) ScriptedWindow[]
        restore(state, bundleID, appURL, timeout) Bool
    }
    class SafariAdapter {
        capture: JXA window tabs and current tab
        restore: AppleScript new document and tabs
    }
    class ChromiumAdapter {
        Chrome, Brave, Edge, Vivaldi, Helium
        capture: JXA tabs, skips incognito
        restore: AppleScript new window and tabs
    }
    class TerminalAdapter {
        capture: JXA tab tty, then WorkingDirectory
        restore: one tab opens its folder, more tabs open a temporary window group file
    }
    class ITermAdapter {
        capture: JXA session tty, then WorkingDirectory
        restore: AppleScript new window, tabs and cd
    }
    class FinderAdapter {
        capture: JXA target folder of each tab, merged by frame
        restore: open the selected folder with Finder
    }
    class CodeEditorAdapter {
        VS Code, Insiders, Cursor, VSCodium, Windsurf
        capture: recent folders and workspaces in state.vscdb
        restore: open the project with the editor
    }
    class ZedAdapter {
        capture: workspaces.paths in the Zed db
        restore: open the project with Zed
    }
    class XcodeAdapter {
        capture: walk up from AXDocument to a project
        restore: open the project with Xcode
    }
    AppAdapter <|.. SafariAdapter
    AppAdapter <|.. ChromiumAdapter
    AppAdapter <|.. TerminalAdapter
    AppAdapter <|.. ITermAdapter
    AppAdapter <|.. FinderAdapter
    AppAdapter <|.. CodeEditorAdapter
    AppAdapter <|.. ZedAdapter
    AppAdapter <|.. XcodeAdapter
    AppAdapters --> AppAdapter : finds by bundle ID
```

### Code editor projects

`ProjectGuess.pick` first limits the recent-project list to projects named in the window title. If no project is named, it uses the whole list. The open file then distinguishes projects with the same name. This keeps a recent nested folder from replacing the parent project that the window has open.

```mermaid
flowchart TD
    Win["Editor window: title and AXDocument"] --> Pool["Projects named in the title, or all recent projects if none"]
    Pool --> Doc{"AXDocument is a file in one of these project folders?"}
    Doc -- Yes --> Deep["the deepest such folder"]
    Doc -- No --> Title{"A part of the title, split at ' — ' and ' - ', is a project name?"}
    Title -- Yes --> Recent["the most recent such project"]
    Title -- No --> None["no state"]
```

Xcode has no recent list that CatWM reads. `ProjectGuess.xcodeProject` walks up from the AXDocument file, at most 12 folders and not past the home folder, to the first folder with an `.xcworkspace`, an `.xcodeproj` or a `Package.swift`.

### Terminal tabs

Terminal scripting has no command that makes a tab. For a window with more than one tab, `TerminalGroup.file` writes a temporary window group file (`type = Window Group`, `WindowList`, a `Window Settings` array with `Tab Working Directory URL` and `TabSelected` for each tab), and CatWM opens it with Terminal. Terminal opens one window with all the tabs. The file is deleted after 30 seconds. The tab profile is the Terminal default profile.

`WorkingDirectory` finds the folder of a terminal tab without a script. It reads the device of the tty, finds the foreground process group of that tty with `sysctl`, and reads the current folder of that process with `proc_pidinfo`.

```mermaid
flowchart LR
    TTY["ttys003"] --> Stat["stat /dev/ttys003"] --> Dev["st_rdev"]
    Dev --> Sysctl["sysctl KERN_PROC_TTY"] --> Group["e_tpgid of the tty"]
    Group --> Pidinfo["proc_pidinfo PROC_PIDVNODEPATHINFO"] --> Folder["file:///path/"]
```

### Automation access

`Automation.access` calls `AEDeterminePermissionToAutomateTarget`. That call can wait for the user, so `Blocking.run` runs it on a background queue and returns a fallback at the timeout.

```mermaid
stateDiagram-v2
    [*] --> Check
    Check --> granted: noErr
    Check --> needsConsent: errAEEventWouldRequireUserConsent
    Check --> notRunning: procNotFound
    Check --> denied: other error
    Check --> needsConsent: timeout
    granted --> [*]: run the script
    needsConsent --> [*]: skip the app
    notRunning --> [*]: skip the app
    denied --> [*]: skip the app
```

A save asks the user (`ask: true`). An open never asks (`ask: false`). If an adapter needs Automation and the app does not allow it, the open uses the next way in the list below.

## Open a template

`TemplateRestorer.restore()` has two phases. `discover()` finds or opens a window for each saved window. `apply()` selects the destination Desktops and interprets the saved display layouts and frames.

Tiling owns placement. `WindowManager.registerPlacements` applies the display layouts, registers the windows and computes tiled frames. `placeWindows` writes and checks the frames through the existing window backend and Animator. `PlacementHolds` suspends hidden windows until a newer scan confirms that they are visible. Templates retain the restore sequence and app-specific failure messages.

```mermaid
sequenceDiagram
    autonumber
    participant Lib as TemplateLibrary
    participant R as TemplateRestorer
    participant RAX as RestoreAX
    participant M as WindowMatch
    participant S as RestoreScheduler
    participant L as Launcher
    participant A as TemplateRestorer+apply

    Lib->>R: restore()
    R->>R: pullOffDesktopWindows()
    loop every 0.3 s, for at most 15 s
        R->>RAX: read(apps) titles, documents and frames
        RAX-->>R: candidates
        R->>M: assign(saved windows, candidates)
        M-->>R: saved ID to window ID
        R->>R: prepareMatchedEarly() sets early frames
        R->>S: step(targets, matched, app states)
        S-->>R: apps to launch and open requests
        R->>L: launch(app, arguments)
        R->>R: perform(request) for each request
    end
    R->>A: apply()
    A->>A: unhide, move to Desktops, set layouts, place frames, hide again
    R-->>Lib: result text for the HUD
```

### One request

Each request opens one saved window. `perform` uses the first way that applies.

```mermaid
flowchart TD
    Req["RestoreRequest"] --> Running{"App is running?"}
    Running -- No --> Refused["noteRefused"]
    Running -- Yes --> Cmd{"launch.command?"}
    Cmd -- Yes --> Shell["Launcher.run(command) with sh -c"]
    Cmd -- No --> HasState{"state is set, and the adapter did not fail?"}
    HasState -- Yes --> Can{"AppAdapters.canRestore?"}
    Can -- Yes --> Adapter["AppAdapters.restore(state)"]
    Adapter -- fails --> Mark["mark adapterFailed, then noteFailed"]
    Mark -.->|next try| HasState
    Can -- No --> Url
    HasState -- No --> Url{"launch.url or document?"}
    Url -- Yes --> Open["Launcher.open(url, withApp:)"]
    Url -- No --> Menu["RestoreAX.newWindow presses New Window or Cmd-N"]
    Menu -- no such item --> Reopen["Launcher.launch(appURL) sends a reopen, like a Dock click"]
    Reopen -- fails --> Failed["noteFailed"]
```

Some apps, such as Electron apps, have no "New Window" item and no Cmd-N. For these apps, CatWM sends a reopen request to the running app, without bringing it to the front. This is the same request that a Dock click sends, and the app makes a window. The request then stays pending until the window appears.

A failed request can try again after 0.5 seconds. It can try 3 times. A started command or a started open does not try again, so a slow app does not get two windows.

### Scheduler phases for one app

```mermaid
stateDiagram-v2
    [*] --> NotRunning
    NotRunning --> GiveUp: cannot open or launch failed
    NotRunning --> Launch: first time
    Launch --> Waiting: app starts
    [*] --> Warm: running and finished launching
    [*] --> Cold: running, still launching
    Waiting --> Cold
    Cold --> Settle: finished launching
    Settle --> Ready: 3 s if no window yet and no document, else 0.75 s
    Warm --> Ready
    Ready --> Ready: one request each 0.3 s, retry after 0.5 s, at most 3 tries
    Ready --> [*]: all saved windows matched or 15 s passed
    GiveUp --> [*]
```

The 3-second wait lets an app bring back its own windows (macOS Resume) before CatWM opens new ones. `WindowMatch` then pairs those windows with the saved windows.

### Match windows

`WindowMatch.assign` runs in four rounds, from the best score to the lowest. In each round it sorts all pairs that fit. A pair with a nearer frame comes first. If two pairs have the same distance, the saved window that was made first gets the window that was made first.

```mermaid
flowchart TD
    Start["Saved window and candidate of the same app"] --> DocCheck{"Saved document differs from the candidate document?"}
    DocCheck -- Yes --> SameTitle{"Candidate has no document and has the same title?"}
    SameTitle -- No --> HasState{"Saved window has app state?"}
    HasState -- Yes --> S0
    HasState -- No --> None["no match"]
    SameTitle -- Yes --> Id
    DocCheck -- No --> Id{"Same window ID and launch date?"}
    Id -- Yes --> S3["score 3: same window"]
    Id -- No --> Doc{"Same document?"}
    Doc -- Yes --> S2["score 2"]
    Doc -- No --> Title{"Same title?"}
    Title -- Yes --> S1["score 1"]
    Title -- No --> NoDoc{"Saved window has no document?"}
    NoDoc -- Yes --> S0["score 0: generic"]
    NoDoc -- No --> None
    S0 --> Generic{"On this Desktop, and new or with the same or no title?"}
    Generic -- No --> None
```

```mermaid
flowchart LR
    R3["Round: score 3"] --> R2["Round: score 2"] --> R1["Round: score 1"] --> R0["Round: score 0"]
    subgraph Round["In each round"]
        Pairs["All fitting pairs"] --> Sort["Sort by frame distance, then saved creation order, then window ID"]
        Sort --> Take["Take a pair if both sides are free"]
    end
```

An existing window with a different document cannot match at score 0, even when its title matches. This keeps restore from reusing an unrelated browser window instead of opening the saved tabs.

A window that a script opened can show another URL while it loads. A saved window with app state can therefore match a new window at score 0. `MatchStability` waits until a score 0 or score 1 match stays the same for 0.6 seconds, but not more than 2 seconds. It ignores frame changes, so an early frame write does not restart the wait.

## The launch dispatcher

`bind = $mod, T, launch, Terminal workspace=2 frame=0,0,50%,100%`

`LaunchRequest` reads the options from the end of the argument. A word with `=` that is not `workspace`, `display` or `frame` stays in the target, so a URL with a query works. The CLI cannot run `launch`, because it can open a `.command` file.

An app name is looked up as `Name.app` in `/Applications`, `/System/Applications`, their `Utilities` folders, `~/Applications`, `/System/Library/CoreServices` (Finder) and `/System/Library/CoreServices/Applications` (Archive Utility, Keychain Access).

`Launcher.resolve` accepts URLs with a scheme, including `mailto:hello@example.com`, `tel:+4712345678` and `obsidian:open?vault=Work`. A URL does not need `//` after the scheme.

```mermaid
sequenceDiagram
    autonumber
    participant K as Hotkeys
    participant WM as WindowManager
    participant L as Launcher
    participant R as refresh()
    participant An as Animator

    K->>WM: dispatch("launch", arg)
    WM->>WM: LaunchRequest(arg) and Launcher.resolve(target)
    alt request has workspace, display or frame
        WM->>WM: add PendingLaunch with bundle ID and current window IDs, for 15 s
    end
    WM->>L: open(target)
    Note over R: the app opens a window
    R->>R: placeArrivals finds a new window
    R->>WM: claimLaunch(window)
    WM->>WM: set floating if frame is set
    WM->>An: animate to the frame on the display
    WM->>WM: assignManagedWindow to the display
    WM->>WM: moveWindow to the workspace
```

```mermaid
flowchart TD
    T["Target text"] --> U{"URL has a scheme?"}
    U -- Yes --> OpenURL[".open(URL)"]
    U -- No --> P{"Starts with / or ~?"}
    P -- Yes --> E{"File exists?"}
    E -- No --> Nil["nil"]
    E -- Yes --> AppExt{"Ends with .app?"}
    AppExt -- Yes --> App[".app(URL)"]
    AppExt -- No --> OpenFile[".open(file URL)"]
    P -- No --> B{"Bundle ID of an app?"}
    B -- Yes --> App
    B -- No --> N{"Name.app in an Applications folder?"}
    N -- Yes --> App
    N -- No --> Nil
```
