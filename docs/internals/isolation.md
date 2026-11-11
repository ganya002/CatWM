# Isolation: Swift 6 language mode

Every target builds in Swift 6 mode, and none opts back to Swift 5. Refresh, layout, the write queue and animation frames are the hot paths, so isolation must not add a hop or a task to them. The only lock on them is `AXWriter`'s, taken twice per step.

## State owners are on the main actor

`WindowManager`, `Animator`, `WindowScanner`, the singletons, the `ObservableObject`s and the panels are `@MainActor`. Refresh reads the window list on the main thread (see `ax-observation.md`) and lays out and animates in one synchronous pass, so an actor would add a hop to every frame for no gain. Their closures that cross threads are `@MainActor @Sendable`.

## Catalogs are Sendable values

`WindowAction`, `Command`, `ConfigOption`, `Release`, `ColorToken` and the other catalog types are `Sendable` structs whose closures are `@Sendable` or `@MainActor @Sendable`. The generators, the CLI and tests read the tables off the main actor, so main-actor catalogs would force a hop to read a constant.

## Cross-thread classes own their state behind a lock

`AXWriter`, `ControlServer`, `ControlConnection`, `Log`'s file, `ScreenRecording`, `AXStalls`, `WindowServerUpdates`, `Embedding` and `EnhancedUI` keep their state in an `OSAllocatedUnfairLock`, which makes them `Sendable` without `@unchecked`. Serial-queue confinement was rejected because the compiler can't check it. `AXWriter` reads its state in one short lock and writes the results back in one more per step, and makes every AX call between them, so a main-thread `step` never waits on AX IPC. `DockBadgePoller` does the same and mutates its fields in place on the way back, so a `markStale` that lands during the AX reads survives.

## Where the main-actor assumption lives

- `MainActor.assumeIsolated` appears twice, each with a `style-ok`. `onMainThread` (`App/MainThread.swift`) serves C callbacks that run on the main run loop and must answer before they return, such as the event taps, where the answer decides whether the event is swallowed. A hop would deliver the event first.
- `NativeTrafficLight` can't import `CatWMKit`, so `TrafficLights.swift` has its own `onMain` for AppKit's accessibility queries, which run on the main thread. `check-style.sh` scans that package too.
- `NotificationCenter.observeOnMain` and `Timer.onMain` wrap the SDK's main-queue delivery, which the SDK types as nonisolated. Handlers receive a `Sendable` payload extracted first, or the owner, so no non-`Sendable` value crosses the boundary.

## Unannotated Apple types

`AXUIElement` and `AXObserver` are immutable CF references whose calls are thread-safe, so `AXSendable.swift` declares one retroactive `@unchecked Sendable` conformance for each instead of a file-wide `@preconcurrency import ApplicationServices`. Two `@preconcurrency` imports remain: `CoreGraphics` in `tapCallback.swift`, whose `CGEvent` has no annotations and arrives on the tap thread, and `Foundation` in `ConfigEngine.swift`, whose `CFRunLoop` the config thread owns. A retroactive conformance on either would make every `CGEvent` or run loop `Sendable` for the whole module, which is a bigger claim than those two files need.

## Deinit

Isolated `deinit` needs a newer runtime than the macOS 14 target. A main-actor owner that must close a panel or stop a clock when it goes away (`Animator`, `WindowResizeFill`) captures those objects and closes them in `DispatchQueue.main.async`, one main turn after release. `PermissionWatcher`, `DockArea`, `WindowResizeScene` and `TrafficLights` lost their `deinit`. Their owners stop or close the first three explicitly. `TrafficLights` removes its flags monitors in `viewDidMoveToWindow` when the view leaves its window.
