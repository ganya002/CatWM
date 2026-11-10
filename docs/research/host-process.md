# Can CatWM run inside a host process

Research for issue #343, part of the map in #339. All code references are to commit `9fec411` (branch `research/host-process`). Sizes: S is a change in one or two files. M touches several files or needs a new seam. L is a structural rewrite or an open design problem.

## Answer

Yes, with one hard limit. CatWM can run inside a host that is not sandboxed (a Developer ID app). It cannot run inside a sandboxed host, and so not in a Mac App Store app. Apple DTS says "It's not possible to use the Accessibility APIs from a sandboxed app", and CatWM's window moves, focus and observers all use Accessibility. It also calls about 33 private SkyLight and related symbols, which App Review guideline 2.5.1 does not allow.

The code is closer to library shape than the entry point suggests. The tiling core already takes its backend, config and surface as arguments (`WindowManager.init` at `Tiling/Manager/WindowManager.swift:114`, `TilingSurface`, `HeadlessSurface`). The work is in everything around it: `main.swift` and `AppDelegate` own the process, 47 `static let shared` singletons assume one instance, and nothing has a teardown path.

Biggest costs, in order:

1. The +2 MB binary budget. Sparkle alone is 2.8 MB on disk, and about 19.5k of 43k source lines are GUI (UI, Settings, Onboarding, Sort, Switcher, Overlays, MenuBar). Splitting the engine from the GUI is the main structural job (L).
2. An engine API with start and stop (M to L). Today there is no `stop()`. The `NSEvent` global monitors, the `NSWorkspace` observers and the AX observers are never removed.
3. Process-wide side effects that would hit the host: `setActivationPolicy(.accessory)` on Settings close, `NSApp.mainMenu`, `NSApp.terminate`, `tccutil reset` on the host's bundle ID, `closePreviousInstances`, signal handlers, a relaunch of the host, and the main run-loop hang monitor with an upload endpoint (each S, about a dozen of them).
4. The Desktop slide guard re-runs `CommandLine.arguments[0]` with `--native-desktop-guard`. In a host that would start a second copy of the host (M).
5. Event taps and the AX observer sources sit on the host's main run loop. A host stall freezes system-wide input while a keybind tap is active (M to L to fix).
6. Singletons and config injection (M for one engine per process; L for many).

Idle memory (+10 MB) is not measured. I did not run anything.

## Summary

| Item | Where | Cost |
| --- | --- | --- |
| Entry point and launch order | `main.swift:3-73` | M |
| `AppDelegate` as the owner of start-up | `App/AppDelegate.swift:7-58` | M |
| `setActivationPolicy` flips | `Settings/Window/SettingsWindow.swift:44,94`, `main.swift:72` | S |
| Main menu | `App/AppDelegate.swift:19,163-183` | S |
| `NSApp.terminate`, relaunch, activate | `Actions/AppActions.swift:21`, `Keys/CapsLockChord.swift:111-113`, `Motion/Windows/Animator.swift:79` and others | S |
| `closePreviousInstances` | `App/AppDelegate.swift:60-86` | S |
| 120 Hz window animation and AX writes | `Motion/Windows/` | S to M |
| Other main-thread timers and display links | `Motion/Kit/MotionKit.swift:51`, `Overlays/Mode/ModeCursor.swift:55` and others | S |
| Singletons and global state | 47 `static let shared`, `Instance` | M (one engine), L (many) |
| Event taps | `Keys/Hotkeys/Hotkeys+setBindings.swift:35` and 3 more | M to L |
| `NSEvent` global monitors, `NSWorkspace` observers | `Tiling/Manager/WindowManager+start.swift:48-168` | M |
| AXObserver | `Tiling/Manager/WindowManager+observe.swift:9-47` | S |
| Own-process filters (`getpid()`) | 13 sites | S |
| Info.plist, `LSUIElement`, build script | `Info.plist`, `build.sh:79-100` | M |
| Resources and SPM bundles | `build.sh:88-96`, MacKeys, PermissionFlow | M |
| Font registration | `UI/Theme/Theme.swift:87-93` | S |
| `Instance`, paths, env vars, log | `App/Instance.swift` | M |
| `UserDefaults` | `Instance.defaults`, 43 uses | S to M |
| Sparkle | `App/Updates/Updater.swift` | S (drop), costs 2.8 MB if kept |
| `CrashWatch` | `Feedback/CrashWatch.swift` | S |
| `PerfMonitor` | `App/Perf/PerfMonitor.swift` | S |
| Signals, `exit()`, `atexit` | `main.swift:50-67`, `App/Instance.swift:129-132` | S |
| Control socket | `Control/ControlServer.swift` | S |
| Login item and CLI link | `App/AppInstall.swift` | S |
| Permissions | `App/Permissions/` | M |
| Onboarding, menu bar item, helper processes | `AppDelegate.swift:10-17`, `Onboarding/`, `DesktopGuardClient.swift:15` | S to M |
| Private SkyLight and AX symbols | 15 files | S to code, L for App Store |
| Migrations on user files | `Migrations/Migrations.swift`, `main.swift:35` | S |

## What already helps

- `WindowManager.init(backend:config:scope:scanner:)` takes its inputs. `ControlServer(manager:)` and `TilingSurface` do the same. `HeadlessSurface` already exists for tests.
- Scoped instances exist: `CATWM_INSTANCE`, `CATWM_SCOPE=pids:...` and `CATWM_KEYS` (`App/Instance.swift:73-100`, `Tiling/Scan/ScopeClaims.swift`). A scoped instance manages only some pids and leaves keys off unless asked. That is close to "every optional feature is off".
- Private symbols are looked up with `dlsym` (`Tiling/Access/PrivateSymbols.swift:4-7`) and fall back to `nil`. A missing symbol disables a feature. It does not fail to link.
- `PermissionFlow` has resource lookups that do not trap (`PermissionFlowResources.swift`, in the dependency checkout).

## Findings by item

### 1. Entry point (`main.swift`)

What it does: `main.swift` is the whole process. In order, it:

- checks the instance (line 3);
- handles hidden sub-commands that exit the process: `--native-desktop-guard` (5), `--write-config-docs` (9), `practice` (14), `docs` (20) and `--write-schema` (30);
- runs `Migrations.run()` (35);
- decides between starting and running the CLI (37-48);
- ignores `SIGPIPE` and installs `SIGTERM`/`SIGINT`/`SIGHUP` handlers (50-67);
- creates `NSApplication.shared`, an `AppDelegate`, sets the policy to `.accessory` and calls `app.run()` (69-73).

Why it conflicts: a library has no `main.swift`. The host's `NSApplication` already runs. Calling `app.run()` again is not possible, and the host owns the delegate. The CLI sub-commands and `exit()` calls must not be linked into the library path at all.

Change: add an engine entry point such as `CatWMEngine.start(config:)` and `stop()`, and keep `main.swift` as a thin caller for the standalone app. The hidden sub-commands stay in the executable target only.

Cost: M.

### 2. `AppDelegate` ownership

What it does: `applicationDidFinishLaunching` (`App/AppDelegate.swift:7-58`) is the real start-up. It:

- closes other instances (8);
- registers fonts (9);
- creates the status item (10-17);
- sets the main menu (19);
- starts Sparkle (20), `CrashWatch` (21) and `PerfMonitor` (22);
- sets `WindowManager.shared.surface = AppSurface()` (23);
- enables the login item and installs the CLI link (28-31);
- starts the permission watcher and then `WindowManager.start()` (34-42);
- shows onboarding, tips and What's New (43-52).

`applicationShouldHandleReopen` (116) opens Settings. `applicationShouldTerminate` (121-131) delays quit until windows are restored. `applicationWillTerminate` (133) cleans up.

Why it conflicts: the host is the app delegate. Most of this list is GUI or process policy that the host owns. Only a small part is engine start-up: surface, `WindowManager.start()`, and the permission-change handler (88-114).

Change: pull the engine part out into a function the host calls. The terminate hook becomes `engine.stop(completion:)`, which restores parked windows and tells the host when it is done. The host calls it from its own `applicationShouldTerminate`.

Cost: M.

### 3. Activation policy

- `Settings/Window/SettingsWindow.swift:44` sets `.regular` when Settings opens. Line 94 sets `.accessory` when it closes. `UI/Gallery/DesignGallery.swift:27` (DEBUG) sets `.regular`.
- In a host, closing Settings would remove the host's Dock icon and menu bar if the host is a normal app.
- The host draws its own GUI, so the embedded build does not link Settings at all. If it did, these calls must go.

Cost: S. Drop with the Settings split.

### 4. Main menu

`App/AppDelegate.swift:19` assigns `NSApp.mainMenu` from `makeMainMenu()` (163-183). That replaces the host's menu. Cost: S. Do not call it in the library path.

### 5. Quit, relaunch and activate

- `NSApp.terminate(nil)` appears at `Actions/AppActions.swift:21`, `MenuBar/Menu/StatusMenu.swift:92`, `MenuBar/Menu/MenuModel+build.swift:107`, `Keys/CapsLockChord.swift:113` and `App/AppDelegate.swift:199`. The `exit` action (summary "Quit CatWM") is a dispatcher, so a keybind or a socket command would quit the host.
- `Keys/CapsLockChord.swift:109-113` runs `sleep 0.7; open -n <Bundle.main.bundlePath>` and then terminates. In a host this relaunches the host app. It fires when Input Monitoring is granted but no events arrive.
- `NSApp.activate(ignoringOtherApps: true)` appears at `Motion/Windows/Animator.swift:79` (fallback of `focusSink`), `Onboarding/WhatsNew/WhatsNew+show.swift:30`, `App/AppDelegate.swift:190,194`, `Settings/Window/SettingsWindow.swift:45`. The Animator one runs during normal use and would pull the host to the front.

Change: route quit and relaunch through a host callback (`onQuitRequested`), remove the relaunch, and make activation a surface call.

Cost: S each, M in total.

### 6. `closePreviousInstances`

`App/AppDelegate.swift:60-86` finds running apps with the same bundle ID or the same executable, then calls `terminate()` and `forceTerminate()` on them. It waits up to 3 s on the main run loop (77-80). In a host it matches the host's own bundle ID, so a second copy of the host would be killed, or the first copy by the second. The user's own standalone CatWM (`local.catwm`) would not match the host's ID, so it would be left alone. That also means two window managers on the same screen. #339 lists this as not yet specified.

Cost: S to remove. The coexistence rule is a design question.

### 7. Main run loop and the 120 Hz budget

How it schedules, verified in code:

- **Window animation.** `WindowFrameClock` (`Motion/Windows/WindowFrameClock.swift:9-18`) is a `CADisplayLink` from `screen.displayLink(target:selector:)`, added to `.main` in `.common` mode. The rate range is 30 to `maximumFramesPerSecond`, so 120 Hz on a ProMotion screen. `Animator.startClock` (`Motion/Windows/Animator.swift:317-336`) picks one screen: the fastest one that contains a destination. The link stops when no trajectories remain (line 210).
- **Main-thread work per frame.** `Animator.tick` (195-215) runs on main. For each moving window it hands a closure to `AXWriter.step`. It does no AX call itself.
- **AX writes.** `AXWriter` (`Motion/Windows/AXWriter.swift:30`) has one serial `DispatchQueue` per pid at `.userInteractive`. Pending steps are coalesced, so a slow app drops frames and does not queue them (81-102). The frame is sampled from the display link timestamp, so a late frame jumps ahead and does not slow the motion.
- **Desktop slide.** `DesktopMotion` (`Motion/Desktop/DesktopMotion.swift:84-110`) creates a `CADisplayLink` for each run, added to `.main`, `.common`. It is a `@MainActor` class and it ends with a timeout `Task`.
- **Panel glide.** `PanelGlide` (`Motion/Kit/MotionKit.swift:51`) uses a 120 Hz `Timer` on the main run loop. `Overlays/Mode/ModeCursor.swift:55` does the same for the cursor.
- **Other timers.** `PermissionWatcher` 1.5 s, `CapsLockChord` 1.5 s, `Tooltip` and `MenuBarTip` 0.25 s, `SortModel` 1/60 s, `DesktopGuardClient` 0.25 s.
- **Threads.** There are many named queues: `catwm.ax.<pid>`, `catwm.focus-write.<pid>`, `catwm.scan.<pid>`, `catwm.focus-read.<pid>`, plus control, permissions and notifications queues. These are created on demand per app.

Why it matters next to a host:

- The display link is a second link on the main run loop. It does not share the host's frame callbacks. The two compete for the same main thread, and per-frame cost is small but unmeasured here.
- A host that blocks the main thread delays the tick, the AX observers, and (most importantly) the event taps (item 9).
- `AXObserver` sources are added in `.defaultMode` only (`WindowManager+observe.swift:31`, `BannerSource.swift:61`). While the host runs a menu-tracking or live-resize loop, those sources do not fire. Switching to `.commonModes` is an S change.
- `PerfMonitor` adds a run-loop observer on the main loop that flags any run-loop pass over 0.25 s as a hang (`App/Perf/PerfMonitor.swift:60-73`). In a host it would measure the host's hangs and treat them as CatWM's.

Change: keep the display link. Make the tick cost observable through `MotionStats` (it already records `timing.ticks`) and measure it inside a host before deciding on a separate thread. Move the AX observer sources to `.commonModes`. Turn off the hang monitor.

Cost: S to M. A dedicated animation thread would be L and is not justified by evidence yet.

### 8. Singletons and global state

Counts (grep, `Sources/CatWM`):

- 47 `static let shared` (and `TabStripFollow` shares a file with `TabStrips`). Examples in the engine: `WindowManager.shared` (`Tiling/Manager/WindowManager.swift:4`), `Hotkeys`, `ControlServer`, `EventBus`, `AXStalls`, `AXBackend`, `FocusDim`, `DesktopWallpaperCover`, `DesktopMenuBarCover`, `WindowServerUpdates`, `CapsLockChord`, `PermissionWatcher`, `LoginItem`. The rest are GUI: `HUD`, `Switcher`, `SettingsWindow`, `SortPanel`, `TabStrips`, `Tips`, `Onboarding`, and so on.
- About 130 other `static let` values that build objects or closures, 7 top-level `let`/`var` globals (`main.swift:51,69,70`, `Session/AX/AXRead.swift:4,14` and others).
- `WindowManager.shared` is read 96 times in 45 files. Most are in `Overlays/Tabs` (20), `Overlays/Split` (7) and menus (6), which are GUI. `Tiling/` itself reaches `FocusDim.shared`, `DesktopWallpaperCover.shared`, `DesktopMenuBarCover.shared`, `WindowServerUpdates.shared`, `AXStalls.shared`, `ControlServer.shared`, `EventBus.shared`, `LoginItem.shared` and `PermissionWatcher.shared`. `Tools/check-style.sh` only rejects `Hotkeys.shared` there (`Tools/check-style.sh:53`).
- `WindowManager.shared` is built from `Config.load()` and `Instance.scope` the first time it is touched. The host cannot hand it a config.
- `Log.file` is a static, opened at first use (`App/Log.swift:32`).

Why it conflicts: one engine per process is fine (a host runs one). The problem is that the engine cannot be built, configured and torn down by the host. Two engines in one process (two scopes) are not possible. The C callbacks (`tapCallback`, `axCallback`, `cursorMoveCallback`) hard-code `Hotkeys.shared` and `WindowManager.shared`.

Change for the minimum: keep a process-wide engine, but construct it from `CatWMEngine.start(config:)` and make `WindowManager.shared` a settable or lazily set value. That is M. Removing the singletons so many engines can run is L and the budget does not need it.

### 9. Event taps, global monitors, HID

Taps (all on the main run loop):

| Tap | Where | Type | Notes |
| --- | --- | --- | --- |
| Keybinds | `Keys/Hotkeys/Hotkeys+setBindings.swift:35` | `cghidEventTap`, head, default | keyDown, flagsChanged, scroll, right mouse. Swallows events. |
| Desktop gestures | `Tiling/Spaces/DesktopGestureTap.swift:20` | session, head, default | |
| Dock window pull | `Tiling/Input/DockWindowPull.swift:16` | session, head, default | |
| Cursor move | `Overlays/Cursor/CursorActions+install.swift:144` | session, tail, listen-only | |

Also: `IOHIDManager` for the Caps Lock key (`Keys/CapsLockChord.swift:74-88`, on the main run loop), `CGEventSource.flagsState` reads, and about 18 `NSEvent` monitors (global and local).

Why it conflicts:

- A default tap on the main thread means the host's main-thread stall delays every key press on the system until the tap times out. `tapCallback` handles `tapDisabledByTimeout` by re-enabling (`Keys/Hotkeys/tapCallback.swift:6-9`), so input comes back, but there is a gap. This is the same risk CatWM has today, but its main thread is only CatWM's. A host's main thread is busier.
- Tokens from `NSEvent.addGlobalMonitorForEvents` are dropped at `WindowManager+start.swift:156-167` and `Tiling/Focus/FocusDim+configure.swift:69`. They cannot be removed. Only 8 `removeMonitor` calls exist in the code base, all for GUI monitors.
- `Hotkeys.disable()` only turns the tap off (`Hotkeys+setBindings.swift:125-128`). There is no code that invalidates and removes the tap and its run-loop source.
- Keys are already optional: `Hotkeys.start` returns early unless `Instance.input.keys` (line 31). Good for "off by default".

Change: add `stop()` to each tap owner and keep the tokens. Optionally run the keybind tap on its own thread with its own run loop. The match tables are read in the callback and written from main, so that needs a lock or a copy-on-write snapshot.

Cost: M for teardown. L for a separate tap thread.

### 10. `NSWorkspace` and distributed notifications

`WindowManager+start.swift:48-153` adds about 9 observers: launch, terminate, power off, hide and unhide, activate, active space, screen parameters, sleep, session resign, and the distributed `com.apple.screenIsLocked`. `PerfMonitor`, `FocusDim`, `ModeFX`, `DesktopWallpaperCover`, `DockBadgeSource`, `BannerSource`, `MacKeyboard` and `PermissionWatcher` add more, and `PermissionWatcher` listens to `com.apple.accessibility.api`.

`WindowManager.notificationObservers` (`WindowManager.swift:107`) is appended to and never read or removed (grep shows only appends). These are additive and harmless in a host, but they leak on stop.

Cost: M with the rest of teardown.

### 11. AXObserver

`WindowManager+observe.swift:9-36` creates one `AXObserver` per regular app on a per-pid scanner queue and adds its source to the main run loop in `.defaultMode`. `release(pid)` removes it (`WindowManager+start.swift:116-126`). There is no "remove all".

`BannerSource` (`Notifications/Sources/BannerSource.swift:42-61`) does the same for Notification Center.

Own-process filters: `pid != getpid()` at `WindowManager+observe.swift:10`, `Tiling/Scan/WindowScanner.swift:205`, `WindowManager+focusObservation.swift:53`, `WindowManager+moveWindow.swift:48`, `WindowManager+prepareDockPull.swift:68`, `Switcher/WindowManager+switcher.swift:10`, `Templates/Model/WindowManager+captureTemplate.swift:106`, `Settings/Rows/AppList.swift:44`, `Tiling/Access/CGWindowInfo.swift:40` and others (13 sites). In a host, the host's own windows are never tiled. `shouldFloat` also floats any window whose bundle ID equals `Bundle.main.bundleIdentifier` (`WindowManager+observe.swift:207`). That is probably right for a host that draws a settings window, but a host that wants its windows tiled cannot have it. This is a product decision.

Cost: S.

### 12. `LSUIElement`, `Info.plist` and the build script

- `Info.plist` is at the repo root. It sets `LSUIElement` true, `CFBundleIdentifier` `local.catwm`, the Sparkle keys (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`), `CatWMReportURL` and `NSAppleEventsUsageDescription`.
- `build.sh:79-100` copies it into the bundle, sets the version with PlistBuddy, copies resources, copies Sparkle and code-signs the app ad hoc with the designated requirement `identifier "local.catwm"`.
- A library has no `Info.plist`. Everything that reads `Bundle.main.infoDictionary` reads the host's: `Updater.swift:12,22`, `PerfMonitor.swift:147,194`, `Feedback.swift:46,115`, `Sidebar.swift:15`, `MenuRowView.swift:24`, `ControlServer.swift:12`. They return empty or the host's version.
- `NSAppleEventsUsageDescription` must be in the host's `Info.plist` for the Session adapters (`osascript`: Terminal, iTerm2, Finder, browsers) to prompt with a useful text.
- The `LSUIElement` flag is not needed: the host decides its own policy. `Bundle.main.bundleIdentifier` checks (`WindowManager+observe.swift:207`, `AppDelegate.swift:64`, `Permission.swift:54`) refer to the host.

Cost: M (move version and config reads behind an `EngineInfo` value that the host passes in).

### 13. Resources, `Bundle.main`, SPM bundles, catalog plugin

- `Package.swift` declares no `resources:` for CatWM. All resources are copied by `build.sh:88-96` into `Contents/Resources`: `Fonts/`, `AppIcon.icns`, `AgentDocs/`, two dependency bundles (`MacKeys_MacKeysCore.bundle`, `PermissionFlow_PermissionFlow.bundle`) and `ThirdPartyNotices.txt`.
- `Bundle.main` is used for resources at `Theme.swift:88` (Fonts) and `main.swift:21` (AgentDocs). `NSApp.applicationIconImage` is used in `UI/Theme/BadgedAppIcon.swift:11` and `Settings/Configs/ConfigSelector.swift:51`.
- `MacKeysCore` reads `Bundle.module` for its JSON data (`mackeys-sdk/swift/Sources/MacKeysCore/Data.swift:226`, `Clips.swift:32`). SPM's generated `Bundle.module` looks for `MacKeys_MacKeysCore.bundle` next to the main bundle's resources or the executable. In a host that bundle is not there unless the host build copies it, and the accessor can trap. `MacKeysCore` is used by the keyboard keycaps and the shortcut recorder, which are GUI.
- `PermissionFlow` documents the same risk and has a non-trapping lookup (`PermissionFlowResources.swift:5-17`).
- `CatalogPlugin` (`Plugins/CatalogPlugin/CatalogPlugin.swift`) is a build-tool plugin that runs `Tools/generate-catalogs.py` and writes `GalleryRegistry.swift` (a DEBUG-only list of gallery examples). It produces source, not a resource bundle, so it has no run-time effect on a host. It does need `/usr/bin/python3` at build time and it runs for every consumer of the target.
- There are no string catalogs, `.xcassets` or `.lproj` folders in `Sources`. UI strings are plain Swift literals, so there is nothing to localize or bundle.

Change: an engine target with no resources, no `MacKeys`, no `PermissionFlow`. Everything that needs a bundle stays in the GUI target.

Cost: M.

### 14. Font registration

`Theme.registerFonts()` (`UI/Theme/Theme.swift:87-93`) reads `Bundle.main.resourceURL/Fonts` and calls `CTFontManagerRegisterFontURLs(..., .process, true, nil)`. It is called once from `AppDelegate:9`. In a host without those fonts it silently does nothing and falls back to the system font (`hasBrandFace` check at line 95). Process scope means the fonts become visible to the host's own UI too. The engine does not draw, so this belongs to the GUI target only.

Cost: S.

### 15. `Instance`, paths and the log

`App/Instance.swift` is a set of `static let` values computed from the environment at first use:

- `CATWM_INSTANCE`, `CATWM_SCOPE`, `CATWM_KEYS` (73-100) and `CATWM_SOCKET` (`ControlServer.swift:7`), `CATWM_RESIZE_SCENE` (`AppSurface.swift:6`).
- Bad values call `exit(2)` (129-132). In a host, a bad variable in the user's shell kills the host.
- Paths: config `~/.config/catwm`, log `~/Library/Logs/CatWM.log`, support `~/Library/Application Support/CatWM`, cache `~/Library/Caches/catwm` (lines 20-29). With no instance id these are the same as the user's own CatWM. An embedded engine would write to the same config file, log, pid file and socket path as a standalone CatWM. The socket start refuses if another process answers (`ControlServer.swift:98-101`), but `Instance.writePid` and the config write do not check.
- `Log.url` is fixed at first use (`App/Log.swift:4-6`), rotated at 2 MB.
- `ControlServer.listen` sets `umask(0o177)` for a moment (`ControlServer.swift:111-114`). `umask` is process-wide, so a host thread that creates a file in that window gets mode 0600.

Change: an `EngineEnvironment` value (config folder, log URL, defaults suite, socket path or none, instance id) passed in at start. Default it so embedded mode never touches `~/.config/catwm`. The named-instance feature is already the right shape for this.

Cost: M.

### 16. `UserDefaults`

`Instance.defaults` returns `.standard` when there is no instance id (`App/Instance.swift:102-106`), so an embedded engine writes `ws.*`, `perf.*`, `didSetUpLaunchAtLogin` and similar keys (`App/DefaultsKey.swift`) into the host's own defaults. 43 call sites use `Instance.defaults`. `Migrations.migrateDefaults` also reads the `local.ouch` and `local.hyprthyst` domains (`Migrations/Migrations.swift:59-72`).

Change: always use a suite (`local.catwm.engine.<host bundle id>` or a name the host gives).

Cost: S to M.

### 17. Sparkle

`App/Updates/Updater.swift` makes an `SPUStandardUpdaterController` that reads `SUFeedURL` and `SUPublicEDKey` from `Bundle.main`. In a host that is the host's updater or nothing. `Sparkle.framework` is 2.8 MB in the installed app, over the whole +2 MB budget. `AppDelegate:20` starts it. The host has its own update path.

Change: the engine target does not depend on Sparkle.

Cost: S.

### 18. `CrashWatch`

`Feedback/CrashWatch.swift` writes a `running` marker, spawns a `/bin/sh` watchdog that reopens `Bundle.main.bundleURL` with `--after-crash` if a `CatWM-*.ips` report appears (73-98), and then uploads crash reports. In a host it would watch for reports named `CatWM-*`, which a host crash never produces, and on a match it would relaunch the host. It also sets up a marker that the host did not ask for. Not needed in embedded mode.

Cost: S (not linked).

### 19. `PerfMonitor`

`App/Perf/PerfMonitor.swift` runs `FrameRun` display links for each animation (`begin("window-move")` at `Animator.swift:330`), hooks a run-loop observer on the main loop (60-73), and can upload reports to the URL in `CatWMReportURL` (`PerfMonitor.swift:147-152`, 172+). It is on by default for the standalone app (`config.perfReports`, only when not a named instance). In a host it would send data about the host's process, with the host's hardware and OS, to CatWM's endpoint. That is a privacy problem as well as a technical one. `Animator` calls `PerfMonitor.shared.begin` unconditionally.

Change: make the monitor opt-in and injectable. Embedded default is off, no upload code.

Cost: S.

### 20. Signal handlers, `exit()`, `atexit`

- `main.swift:50` sets `SIGPIPE` to ignore. `ControlServer.start` does it again (`ControlServer.swift:27`) and so does `ControlCLI` (`ControlCLI.swift:5`). It is process-wide.
- `main.swift:52-67` replaces the handlers for `SIGTERM`, `SIGINT` and `SIGHUP` with dispatch sources. The handler restores parked windows and then calls `exit(0)`. A host has its own handlers. Installing these would replace them.
- `exit()` calls: `main.swift` (11, 24, 27, 32, 42, 47, 62), `App/Instance.swift:131`, `Tiling/Spaces/DesktopGuard.swift` (the helper), `ControlCLI.swift` (126, 138, 143). Only `Instance.fail` and the signal handler can run inside an embedded engine.
- No `atexit` or `NSSetUncaughtExceptionHandler` calls (grep found none). `fatalError` appears twice in the engine: `Config/Options/ConfigOption.swift:127` and `Settings/Rows/OptionRow.swift:76`.
- A crash or a host `exit` while windows are parked off-screen leaves them parked (virtual workspaces). The standalone app handles clean exit with `restoreHiddenWindows` (`Tiling/Manager/WindowManager+isOnHomeSpace.swift:127`) and has recovery state (`saveTilingRecovery`) for the next start. An embedded engine needs a `stop()` that the host must call on every exit path, plus the same recovery on the next start.

Change: no signal handlers in the library. A documented `engine.stop(completion:)`.

Cost: S for the handlers, M to make exit safe.

### 21. Control socket

`Control/ControlServer.swift` listens on a Unix socket (`~/.config/catwm/catwm.sock` unless `CATWM_SOCKET`), has its own queues and calls `CommandRegistry` on the main queue. `ControlServer(manager:)` already takes a manager (line 19), but `.shared` is used at `WindowManager+start.swift:24`. The `hello` reply reports `Bundle.main` version and `getpid()`. It is a good fit as an optional feature: the host can leave it off. If it is on, the path must be per host.

Cost: S.

### 22. Login item and CLI link

`App/AppInstall.swift`: `LoginItem` uses `SMAppService.mainApp` (line 6, 12, 38). In a host that registers the host as a login item. `enableOnFirstLaunch` does this without asking (`AppDelegate.swift:29`). `CommandLineTool.install` symlinks the host executable as `catwm` in `/usr/local/bin` or `~/.local/bin` when its path contains `/Applications/` (`AppInstall.swift:52-80`). Both must not run in a host. `WindowManager+status.swift:10` reads `LoginItem.shared`.

Cost: S.

### 23. Permission prompts

`App/Permissions/Permission.swift` checks four permissions: `AXIsProcessTrusted()` (13), `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` (14), a ScreenCaptureKit test shot (`ScreenRecording.swift`) and a read test for the notification database (Full Disk Access). `PermissionWatcher` polls every 1.5 s and listens for `com.apple.accessibility.api`.

Problems in a host:

- `Permission.reset()` runs `tccutil reset <service> <Bundle.main.bundleIdentifier>` (line 54). It is called when Accessibility is revoked (`AppDelegate.swift:112`). In a host that resets the host's entry for Accessibility, Input Monitoring, Screen Recording or Full Disk Access.
- `PermissionGuide.show` opens a `PermissionFlow` panel and passes `Bundle.main.bundleURL` as the app to drag into System Settings (98). The host should own this UI.
- `closeSettingsWindows` closes System Settings windows through AX (58-64).
- The 1.5 s poll runs `IOHIDCheckAccess` and a `SCScreenshotManager` capture for Screen Recording, even if the host never uses that feature (`ScreenRecording.swift:30-42`).

Change: the engine reports needed and granted permissions (a read-only API) and never prompts, resets or shows UI. The host does the prompting. Screen Recording and Full Disk Access checks only run if the feature that needs them is on.

Cost: M.

### 24. Onboarding, menu bar item, helper processes

- Menu bar item: `NSStatusBar.system.statusItem` in `AppDelegate.swift:10-17`, icons from `MenuBar/`. GUI only. The host draws its own.
- Onboarding, tips, What's New, welcome and tour are started from `AppDelegate:43-52`. GUI only. `Onboarding+shouldShow.swift:118` also polls with a 0.5 s timer.
- Helper processes that re-run the app executable: `Coach+start.swift:55-59` (`practice`, onboarding only) and `Tiling/Spaces/DesktopGuardClient.swift:15-16`. The second one is not onboarding. It runs with `CommandLine.arguments[0]` and `--native-desktop-guard <pid>`. It is the Desktop-slide recovery process. It restores Space transforms if CatWM dies mid-slide (`DesktopGuard.swift`). In a host, `CommandLine.arguments[0]` is the host executable, which has no `--native-desktop-guard` branch. The result is a second copy of the host app.

Change: ship the guard as its own small executable inside the host's bundle, and let the host pass its path. Or run it in-process, which loses the crash recovery. Or leave virtual-workspace Desktop slides off by default.

Cost: M.

### 25. Private APIs and global C state

Private symbols, all found with `dlsym` (no link-time dependency):

- `SLS*` from SkyLight in `Tiling/Access/Spaces.swift`, `Tiling/Scan/WindowServerList.swift`, `Tiling/Scan/WindowServerQuery.swift`, `Tiling/Spaces/DesktopMenuBarNative.swift`, `Tiling/Spaces/DesktopMenuBarCover.swift`, `Tiling/Focus/FocusDim.swift:97-98`, `Motion/Windows/WindowSceneCapture.swift:18-27`, `UI/Chrome/OverlaySpace.swift`, `UI/Chrome/ScreenShape.swift`, `Overlays/Mode/ModeCursor.swift`.
- `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo` and `GetProcessForPID` in `Tiling/Focus/WindowFocus.swift:15-18`.
- `_AXUIElementGetWindow` from HIServices in `Session/AX/AXRead.swift:16`.
- Objective-C bridge classes of SkyLight (`SLSBridged*Operation`) and a Mach-O symbol-table walk to find a private C++ function in `Tiling/Spaces/NativeSpaceMove.swift:29-40,150-200` and `Tiling/Spaces/DesktopBridge.swift`.

In-process, these use the host's SkyLight connection (`SLSMainConnectionID`). Two of them change connection-wide state, which becomes the host's state:

- `Overlays/Mode/ModeCursor.swift:22-24` sets `SetsCursorInBackground` on the process's connection.
- `UI/Chrome/OverlaySpace.swift:18-24` creates a Space at absolute level `Int32.max` and shows it, once per process.

Both belong to GUI features. The window-management symbols (list, query, focus, Spaces) are read-only or act on other apps' windows.

Cost: S in code. The App Store problem is separate (see the sandbox section).

### 26. Migrations on user files

`main.swift:35` runs `Migrations.run()` on every start. It moves `~/.config/ouch` into `~/.config/catwm`, copies `~/.config/hyprthyst`, and copies keys from two legacy defaults domains (`Migrations/Migrations.swift`). That is a standalone-app job. An embedded engine must not touch these paths.

Cost: S (not linked).

## TCC and sandbox (Apple sources)

I fetched each page below with the fetch tool. A few quotes come from a summarizing step in that tool, so I mark the ones I could only check that way.

### Does TCC attribute the permissions to the host?

**Accessibility.** The doc for `AXIsProcessTrustedWithOptions` says it "Returns whether the current process is a trusted accessibility client."
[developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions). Code in a linked framework runs in the host process, so "the current process" is the host. That follows from the text. Apple does not say "framework" in it, so treat the framework case as inference.

**Responsible code.** Quinn "The Eskimo!" describes the rule in *On File System Permissions*: "The MAC privilege mechanism is heavily dependent on the concept of *responsible code*. For example, if an app contains a helper tool and the helper tool triggers a MAC prompt, we want: The app's name and usage description to appear in the alert. The user's decision to be recorded for the whole app, not that specific helper tool. That decision to show up in System Settings under the app's name."
[developer.apple.com/forums/thread/678819](https://developer.apple.com/forums/thread/678819). So for a helper process the app is blamed. For in-process code there is no helper step: the process is the host. The grant, the prompt name and the Settings row are the host's. I found no Apple text that names frameworks or SPM libraries explicitly. Unconfirmed as a quote, but consistent.

**Input Monitoring (CGEventTap).** Quinn: "It *is* possible for a sandboxed app to use the Input Monitoring privilege. I regularly test this. Specifically, I'm using the `CGEventTap` API."
[developer.apple.com/forums/thread/780626](https://developer.apple.com/forums/thread/780626). The tap permission is held by the process that creates the tap, so the host. The `CGEvent.tapCreate` doc still describes the old rule ("Access for assistive devices is enabled") and says nothing about Input Monitoring:
[developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)).
I could not confirm from a primary source which tap options need Accessibility and which need Input Monitoring. CatWM's keybind tap is `.defaultTap` (it swallows events), the cursor tap is `.listenOnly`.

**Screen Recording and Full Disk Access.** The Apple docs I could fetch (`CGRequestScreenCaptureAccess`, `CGPreflightScreenCaptureAccess`, `CGRequestListenEventAccess`) have no description text, only the signature. The Apple Platform Security guide page on app access ([support.apple.com/guide/security/secddd1d86a6/web](https://support.apple.com/guide/security/secddd1d86a6/web)) lists Accessibility, Files and Folders, full storage access and Automation, and does not name Input Monitoring or Screen Recording. I found no primary text that says the host process is blamed for these two. Unconfirmed in words, but they use the same mechanism as above.

**Usage strings.** `NSAppleEventsUsageDescription` "is required if your app uses APIs that send Apple events"
([doc](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)).
Quinn says the alert shows "The app's name and usage description" of the responsible app (thread 678819, above). So a library cannot ship its own string. The host's `Info.plist` must carry `NSAppleEventsUsageDescription`, and the prompt shows the host's name. I found no Info.plist usage-string key for Accessibility, Input Monitoring, Screen Recording or Full Disk Access in the Apple docs. Unconfirmed that none exists. In my reading the system supplies the text for those.

**Host signature changes.** Quinn: "This relies on your code having a stable code signing identity. If your code is unsigned, or signed ad hoc (Signed to Run Locally in Xcode parlance), the system can't tell that version N+1 of your code is the same as version N, and thus you'll encounter excessive prompts."
[thread 678819](https://developer.apple.com/forums/thread/678819). Apple does not say what happens to an existing grant when the designated requirement changes (the page points to TN3127). From the quote: a host that re-signs with a different identity, or ships ad hoc builds, makes users grant again. A statically linked CatWM is part of the host's executable and does not add its own identity. A separate signed CatWM framework or helper is a different code identity, and it must share the host's Team ID or the host must set `com.apple.security.cs.disable-library-validation`. Apple: library validation "prevents a program from loading frameworks, plug-ins, or libraries unless they're either signed by Apple or signed with the same Team ID as the main executable."
[doc](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation).
Also from thread 678819: "TCC expects its bundled clients ... to use a native main executable." A host with a script or non-Mach-O main executable has trouble anyway.

**macOS 27 name.** The repo's own `PermissionFlow` resource keys say System Settings calls the Accessibility page "Device Control and Data Access" on macOS 27 (`PermissionFlowResources.swift:22-35`). Other reports say the same (GitHub issues, vendor docs). I found no Apple page for this. Unconfirmed from Apple. Any host text that names the pane must handle both names.

### Can a sandboxed or App Store app use the Accessibility API?

No, according to Apple DTS, in four separate threads:

- "It is not possible to use the accessibility API from a sandboxed app." Apple staff, April 2024. [thread 749494](https://developer.apple.com/forums/thread/749494). (Summarized by the fetch tool; the poster name is not shown.)
- Quinn, April 2025: "It's not possible for a sandboxed app to use the Accessibility privilege [1]. Specifically, DTS doesn't support folks using general accessibility APIs is sandboxed apps." Footnote: "Without employing temporary exception entitlements." About App Store policy: "I don't work for App Review and thus can't comment on the second part." [thread 780626](https://developer.apple.com/forums/thread/780626).
- Quinn, July 2025: "We do not support the Accessibility APIs in sandboxed apps." The thread title is "AXIsProcessTrusted returns true, but AXUIElementCopyAttributeValue fails with .cannotComplete", and Quinn calls the failing behavior correct. So `AXIsProcessTrusted()` is not a reliable test in a sandbox. [thread 794253](https://developer.apple.com/forums/thread/794253).
- Quinn, October 2025, on a window-manager app: "It's not possible to use the Accessibility APIs from a sandboxed app." He says the entitlement `com.apple.security.accessibility` "isn't a thing", and "AFAICT your only path forward here is to directly distribute your app using Developer ID signing." He declines to speak for App Review. [thread 805556](https://developer.apple.com/forums/thread/805556).

App Review Guideline 2.4.5(i): Mac App Store apps "must be appropriately sandboxed". [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). Together: a Mac App Store host is sandboxed, so it cannot use AX, so it cannot host CatWM's window management. A sandboxed host that is distributed outside the store has the same limit, because the limit is the sandbox. I found no primary statement about macOS 26 or 27 changing this. Unconfirmed for the newest releases.

One forum poster says other window managers are on the Mac App Store. That is not an Apple source and I could not confirm it. The "temporary exception entitlements" footnote is the only hint of a path, and I did not find an Apple page that lists an exception for Accessibility. Unconfirmed.

### Event taps and Input Monitoring in a sandbox

Quinn (thread 780626 above): a sandboxed app can use Input Monitoring through `CGEventTap`. That covers listen-only taps, such as CatWM's cursor tap. CatWM's keybind tap swallows events and so is a default tap. I found no Apple statement on default taps in a sandbox, so whether it works there is unconfirmed. The question is moot if AX is already blocked.

### Private SkyLight and CGS APIs

Guideline 2.5.1: "Apps may only use public APIs and must run on the currently shipping OS."
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). SkyLight is under `/System/Library/PrivateFrameworks/`, and `_AXUIElementGetWindow`, `_SLPSSetFrontProcessWithOptions` and the `SLSBridged*` classes have no public headers. By the plain reading they are private APIs, so a Mac App Store build cannot ship them. The guideline does not name SkyLight, and loading symbols with `dlsym` does not appear in the text as an exception. Apple does not say how App Review detects `dlsym` use. Unconfirmed.

Without them CatWM loses: the on-screen window list and Space queries (`WindowServerList`, `WindowServerQuery`, `Spaces`), the precise focus path (`WindowFocus`), native Desktop moves and slides, dim blur, the overlay Space, window capture for the resize scene and the cursor property. Some have public fallbacks (`CGWindowListCopyWindowInfo`, `NSWorkspace` activation). Others (native Desktop creation and moves) have none.

Other App Review lines that would bite a store build, quoted from the same page: 2.4.5(iii) no auto-launch "without consent" (login item), 2.4.5(vii) "must use the Mac App Store to distribute updates" (Sparkle).

## Sources

- AXIsProcessTrustedWithOptions: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- CGEvent.tapCreate: https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)
- NSAppleEventsUsageDescription: https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription
- Disable Library Validation entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation
- Quinn, On File System Permissions: https://developer.apple.com/forums/thread/678819
- Quinn, How to access files when running Xcode tests (responsible code for xctest): https://developer.apple.com/forums/thread/718525
- Apple staff, sandbox and Accessibility: https://developer.apple.com/forums/thread/749494
- Quinn, Clarification on Accessibility and Input Monitoring APIs for App Store Apps: https://developer.apple.com/forums/thread/780626
- Quinn, AXIsProcessTrusted returns true, but AXUIElementCopyAttributeValue fails: https://developer.apple.com/forums/thread/794253
- Quinn, Unable to submit my macOS window-manager app: https://developer.apple.com/forums/thread/805556
- App Review Guidelines (2.4.5, 2.5.1): https://developer.apple.com/app-store/review/guidelines/
- Apple Platform Security, Controlling app access to files in macOS: https://support.apple.com/guide/security/secddd1d86a6/web

Not primary and not relied on: GitHub issues and blogs about the macOS 27 pane rename and MDM changes. I did not check the WWDC26 privacy lab video.
