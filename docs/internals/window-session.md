# Window session

The `WindowSession` module saves and opens app windows. The app imports it with `import WindowSession`. The module does not know about Ouch workspaces, layouts or Desktops. The code in `Sources/ouch/Templates/` uses the module and changes the Ouch state.

## Module map

```mermaid
flowchart TB
    subgraph App["ouch target: Templates/ and Tiling/Manager/"]
        direction LR
        Library["TemplateLibrary"]
        Capture["WindowManager+captureTemplate<br/>TemplateCaptureAssembler"]
        Restorer["TemplateRestorer<br/>+apply, +pull"]
        LaunchCmd["WindowManager+launch"]
    end

    subgraph WS["WindowSession module"]
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

`WorkspaceTemplate` stays in the app. Its `SavedWindow` is the module type. The `state` and `launch` fields are optional, so an old `templates.json` file loads without a change.

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

`AppState.tabs` holds one URL for each tab. A browser tab is an `http` or `https` URL. A Terminal tab, an iTerm2 tab or a Finder window is a `file` URL of a folder.

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
        WM->>SC: capture(windows, consentWait: 30 s, scriptTimeout: 3 s)
        par one task for each app with an adapter
            SC->>AU: access(bundleID, ask: true)
            AU-->>SC: granted, denied, needsConsent or notRunning
            SC->>AD: capture(bundleID)
            AD-->>SC: ScriptedWindow list
            SC->>SC: attach(scripted, to: windows)
        end
        SC-->>WM: AppState for each window ID
        WM->>WM: set SavedWindow.state
    end
    WM-->>UI: WorkspaceTemplate
```

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

An adapter reads the state of one app and opens it again. JavaScript for Automation (JXA) reads the state and returns JSON. AppleScript opens the state. `AppScript` runs each script in an `osascript` process. A timer stops the process at the timeout, so an app that does not respond cannot stop Ouch.

```mermaid
classDiagram
    class AppAdapter {
        <<protocol>>
        Set~String~ bundleIDs
        Bool restoreNeedsAutomation
        capture(bundleID, timeout) ScriptedWindow[]
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
        restore: open the selected folder with Terminal
    }
    class ITermAdapter {
        capture: JXA session tty, then WorkingDirectory
        restore: AppleScript new window, tabs and cd
    }
    class FinderAdapter {
        capture: JXA target folder of each window
        restore: open the folder with Finder
    }
    AppAdapter <|.. SafariAdapter
    AppAdapter <|.. ChromiumAdapter
    AppAdapter <|.. TerminalAdapter
    AppAdapter <|.. ITermAdapter
    AppAdapter <|.. FinderAdapter
    AppAdapters --> AppAdapter : finds by bundle ID
```

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

`TemplateRestorer.restore()` has two phases. `discover()` finds or opens a window for each saved window. `apply()` moves the windows to their Desktops, sets the layouts and places the frames.

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

Some apps, such as Electron apps, have no "New Window" item and no Cmd-N. For these apps, Ouch sends a reopen request to the running app, without bringing it to the front. This is the same request that a Dock click sends, and the app makes a window. The request then stays pending until the window appears.

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

The 3-second wait lets an app bring back its own windows (macOS Resume) before Ouch opens new ones. `WindowMatch` then pairs those windows with the saved windows.

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

A window that a script opened can show another URL while it loads. A saved window with app state can therefore match a new window at score 0. `MatchStability` waits until a score 0 or score 1 match stays the same for 0.6 seconds, but not more than 2 seconds. It ignores frame changes, so an early frame write does not restart the wait.

## The launch dispatcher

`bind = $mod, T, launch, Terminal workspace=2 frame=0,0,50%,100%`

`LaunchRequest` reads the options from the end of the argument. A word with `=` that is not `workspace`, `display` or `frame` stays in the target, so a URL with a query works. The CLI cannot run `launch`, because it can open a `.command` file.

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
    T["Target text"] --> U{"Has ://?"}
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
