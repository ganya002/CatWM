# Isolation: Swift 6 language mode

Every target builds in Swift 6 mode, and none opts back to Swift 5. Refresh, layout, the write queue and animation frames are the hot paths, so isolation must not add a hop or a task to them. The only lock on them is `AXWriter`'s, taken twice per step.

## State owners are on the main actor

`WindowManager`, `Animator`, `WindowScanner`, the singletons, the `ObservableObject`s and the panels are `@MainActor`. Refresh reads the window list on the main thread (see `ax-observation.md`) and lays out and animates in one synchronous pass, so an actor would add a hop to every frame for no gain. Their closures that cross threads are `@MainActor @Sendable`.

## Catalogs are Sendable values

`WindowAction`, `Command`, `ConfigOption`, `Release`, `ColorToken` and the other catalog types are `Sendable` structs whose closures are `@Sendable` or `@MainActor @Sendable`. The generators, the CLI and tests read the tables off the main actor, so main-actor catalogs would force a hop to read a constant.

## Cross-thread classes own their state behind a lock

`AXWriter`, `ControlServer`, `ControlConnection`, `Log`'s file, `ScreenRecording`, `AXStalls`, `WindowServerUpdates`, `Embedding` and `EnhancedUI` keep their state in an `OSAllocatedUnfairLock`, which makes them `Sendable` without `@unchecked`. Serial-queue confinement was rejected because the compiler can't check it. `AXWriter` reads its state in one short lock and writes the results back in one more per step, and makes every AX call between them, so a main-thread `step` never waits on AX IPC. `DockBadgePoller` does the same, and writes back only the fields it changed, so the poll never replaces state with a stale snapshot.

## Where the main-actor assumption lives

- `MainActor.assumeIsolated` appears twice, each with a `style-ok`. `onMainThread` (`App/MainThread.swift`) serves C callbacks that run on the main run loop and must answer before they return, such as the event taps, where the answer decides whether the event is swallowed. A hop would deliver the event first.
- `NativeTrafficLight` can't import `CatWMKit`, so `TrafficLights.swift` has its own `onMain` for AppKit's accessibility queries, which run on the main thread. `check-style.sh` scans that package too.
- `NotificationCenter.observeOnMain` and `Timer.onMain` wrap the SDK's main-queue delivery, which the SDK types as nonisolated. Handlers receive a `Sendable` payload extracted first, or the owner, so no non-`Sendable` value crosses the boundary.

## Unannotated Apple types

`AXUIElement` and `AXObserver` are not `Sendable`. `AXReference` (`Tiling/Access/AXReference.swift`) is a package-internal `@unchecked Sendable` wrapper that carries one across a queue hop, with a `style-ok` that names AX's own locking as the reason it is safe. `Window` and `WindowScanner.Found` hold their element in one, and the scan-queue closures that capture an element or an observer wrap it first. That includes `watch(_:)`, which adds notifications on the scan queue while the observer's run-loop source is live on main, so the observer isn't immutable and only AX's locking makes that safe. A retroactive `Sendable` conformance was rejected: it is global, so it would make `AXUIElement` `Sendable` inside every host that embeds CatWM and switch off a Swift 6 check in their code. File-wide `@preconcurrency import ApplicationServices` was rejected for the same reason of breadth.

Two `@preconcurrency` imports remain. `CoreGraphics` in `tapCallback.swift`: tap sources run on `CFRunLoopGetMain()`, so the `CGEvent` is already on the main thread, but the compiler can't see that handing it to the main actor is synchronous. `Foundation` in `ConfigEngine.swift`: the config thread owns its `CFRunLoop`.

## Deinit

Isolated `deinit` needs a newer runtime than the macOS 14 target. A main-actor owner that must close a panel or stop a clock when it goes away (`Animator`, `WindowResizeFill`) captures those objects and closes them in `DispatchQueue.main.async`, one main turn after release. `PermissionWatcher`, `DockArea`, `WindowResizeScene` and `TrafficLights` lost their `deinit`. Their owners stop or close the first three explicitly. `TrafficLights` removes its flags monitors in `viewDidMoveToWindow` when the view leaves its window.

## A scoped instance ends with its scope

An incident left two scoped test instances on the user's screen for over an hour. They were orphans (parent pid 1) whose `CATWM_SCOPE` was `pids:1`, and nothing ended them because the scope never exits. Two rules close this.

**A scope with pid 1 is refused at start** (`WindowScope.refusal`, exit code 2). launchd never exits, so such an instance would never end, and no test owns launchd. A shell's `$PPID` becomes 1 once its parent dies, which is the likely way a test ends up with `pids:1`. The scope must name a process that the test owns, such as `$$`.

**The instance quits when every pid of its scope has exited** (`ScopeLifetime`, started by `AppDelegate` before any window work). It watches each pid with a `DispatchSource` process source and checks once at start for a pid that is already gone, because a source on a dead pid never fires. The check reads `proc_pidinfo` and treats a zombie as gone, because `kill(pid, 0)` still succeeds for a zombie that its parent has not reaped. Quitting is `SIGTERM` to itself, which takes the normal path in `main.swift` (restore parked windows, remove the pid file and claim). The alternatives were a poll (a timer that wakes an idle app, which the perf budgets count) and reusing `ScopeClaims`' owner watches. `ScopeClaims` watches the owner of a claim for the other instances, not the pids inside a scope, and it exists only on the unscoped side. A scope that holds only apps the test launches ends the instance when those apps quit, so a harness that wants a longer life adds its own pid (`Tools/smoke.py` does).

**Only the default instance relaunches itself** (`InstancePaths.mayRelaunchItself`). The Input Monitoring relaunch in `CapsLockChord` runs `open -n <bundle>`, and the crash watchdog in `CrashWatch` runs `open <bundle>`. Both start the bundle as the user's default app, so a named instance that took either path would leave an extra default CatWM behind. `open` does not pass the caller's environment on, so a relaunch never carried `CATWM_*` into `/Applications`. The danger was the extra default instance, so both paths now stay off for a named instance, scoped or not.

## What a scoped instance can still reach

Checked in code, no leak found. `restrict` turns Desktops off, so the Desktop slide, `DesktopGuardClient`, the wallpaper and menu bar covers, `WindowServerUpdates` leases in `moveNativeWindow`, native space moves and empty-Desktop removal never run. The commands that would start them are in `refusedCommands`. `restoreHiddenWindows` and parked-window restore iterate `windows`, which holds only scope pids, and the scanner drops other pids before the manager sees them, so cached AX elements belong to the scope. `GlobalInput` leaves out the event taps, Caps Lock, the pointer and the focus sink. What a scope without a display still draws on the user's screens is the next section's subject.

## A scope with a display draws nothing on the user's screens

`CATWM_SCOPE=...;display:<uuid>` makes the instance contained (`Instance.isContained`). Everything it draws goes to that display or is not drawn. One chokepoint for each kind of drawing, because patching every call site would miss the next one.

- **Screens.** `NSScreen.userScreens` returns only the scope's display, and only for a contained instance. Before this, every CatWM process dropped every agent display from `userScreens`, so a scope naming one saw no screens at all. Mode effects, dimming and `Screen.all` read this one list.
- **Panels.** Every panel is a `CatWMPanel`, which clamps its frame into the scope's display on each `setFrame`, `setFrameOrigin`, `setFrameTopLeftPoint` and each way of ordering it front. A display that is gone means the panel never shows. Callers keep choosing a screen with `NSScreen.main` or the pointer, so the clamp is what keeps a HUD or tab strip off the user's screen. The alternative, an audit of the 24 files that make panels, would break at the next new panel.
- **Status item and menu.** No `NSStatusItem` is made. The status menu, the menu bar tip and the sort nudge anchor to it, so they have nothing to open from.
- **Windows and prompts.** `SettingsWindow.show` (also reached by reopening the app), the update alert, onboarding, the design gallery and `PermissionGuide.show` do nothing. `PermissionGuide.show` is the single path for the Accessibility and other permission prompts. The unnamed-only surfaces (Tips, What's New, the updater, crash reports, the login item) were already off for any named instance.
- **The focus sink** is never ordered front, because a scoped instance has no pointer or focus handling.

An untrusted contained instance therefore just logs that it has no Accessibility permission. `ScopeLifetime` still ends it with its scope pids.

`PermissionGuide.show` is the exception that keys on the scope alone, not on the display. A prompt opens System Settings, a separate process that no clamp can contain, and runs PermissionFlow's 30 Hz window tracker and 60 Hz panel animation. A scoped instance without a display (perf CI, which has no user CatWM to open an agent display) and without Accessibility would take that path on every launch, and CI measured a startup of 390–530 ms and an idle spike in the first seconds where a contained run takes about 100 ms and none. A scoped instance exists to be driven by a test, so nobody is there to answer the prompt.

## The perf app scenario on an agent display

`Tools/perf.py` opens an agent display through the running user CatWM (`Sandbox`, one connection for the whole run) and scopes each instance with `;display:<uuid>`. All parallel runs share the display, since the instances manage no windows. The display belongs to the connection, so the kernel closes it if perf.py dies, and `ScopeLifetime` ends the instances with perf.py. With no CatWM socket, or one without `agent.open` (a build from before the agent display), CI keeps the old behaviour (scoped to its own pid on the real display, whose screen nobody watches) and says so. Anywhere else the script stops and asks for an agent display or `--skip-app`, because a fallback to the real display would put test instances on a developer's screen.

The idle rows start once macOS has finished measuring the launch, not at a fixed second. AppKit's launch measurement (`libapp_launch_measurement`) re-arms a 3 ms main-queue timer until about ten firings in a row arrive on time, and gives up after 500. A Mac passes it within a fraction of a second. On the CI virtual machine the timers fire late, so the check runs to its limit and costs about 8 ms a second on the main thread and 5 on a dispatch thread for 5–10 s, which the idle rows measured as CatWM's. `perf.py` follows the measurement's own log (`ApplicationLaunchExtendedResponsive`, or its "Bailing" line) for each pid and starts the idle window after it, with a 20 s limit. The alternatives were to end the measurement from inside CatWM, which needs private API and only hides it, and to start the idle window later by a fixed amount, which guesses a VM's speed. The startup row still counts the check, because it runs inside the launch.

## An engine on a fake never reaches the user's input

An engine built on `FakeBackend` must never reach the user's input: the perf tool, CI perf and `swift test` must not post a key, press the pointer, warp it or switch a Desktop. The engine reaches all of these through `WindowBackend`, and `RealInput` refuses the ones that skip it (see `fake-backend.md` for the decision and the alternative). The scope's `GlobalInput` was not enough: an unscoped manager has `pointerAndFocus` on, and a fake manager is unscoped.
