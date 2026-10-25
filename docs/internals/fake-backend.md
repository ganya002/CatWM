# Fake backend tests

`WindowBackend` (`Tiling/Access/WindowBackend.swift`) is the boundary between the tiling engine and macOS. `AXBackend.shared` sends each call to AX, the window server and `NSWorkspace`. A test can give `WindowManager` a `FakeBackend` (`Tests/CatWMTests/Support/FakeBackend.swift`) instead. The real engine then runs on in-memory windows and screens. The test needs no permissions, no GUI and no real app windows.

Use a fake backend test when you change refresh, layout, placement, focus or the AX write path. Do not copy engine logic into the test. Make a change in the fake, run the engine, and then examine the result.

## Write a test

1. Make a `FakeBackend` and add a screen with `addScreen(frame:visible:)`.
2. Make the manager with `fake.makeManager()`. It uses the default config text, and it sets these values: no virtual workspaces, no animation, no mouse warp, no focus follows mouse, no gaps and no padding. Change more values in its closure. Do not use `Config.load()`, because it reads and can write the config file of the user.
3. Add windows with `addWindow(pid:bundleID:frame:title:minSize:resizable:)`. Each pid must be negative, so no AX call can go to a real app.
4. Call `await fake.settle(manager)`. It runs `scanAndRefresh(then:)` and then waits for the pending AX writes. It does this again until a round writes no frame and the manager knows each fake window.
5. Make a user change with `close`, `quit`, `minimize`, `userMoves` or `userFocuses`. Then call `settle` again.
6. Examine `fake.frame(of:)`, `fake.writes`, `fake.focused(in:)`, `fake.frontmost` and the manager state.

```swift
@Test @MainActor func twoWindowsSplitTheScreen() async {
    let fake = FakeBackend()
    let screen = fake.addScreen()
    let manager = fake.makeManager()
    let first = fake.addWindow(), second = fake.addWindow()
    await fake.settle(manager)
    #expect(fake.frame(of: first).width == screen.visible.width / 2)
    #expect(fake.frame(of: second).minX == screen.visible.midX)
}
```

## Wait for an event

Do not use a sleep or a fixed run-loop wait. `Tools/check-style.sh` rejects them in tests. Wait for the engine:

- `settle(_:)` waits for a scan, a refresh and the AX writes.
- `wait(_:until:)` waits until a condition is true. It examines the condition each time the manager calls `onChange`.

Some engine steps start on a timer, for example the frame check 0.12 s after a placement, which finds the minimum size of a window. Use `wait(_:until:)` for the result of such a step, and then call `settle` again. The suite has a time limit of one minute, so a missing event stops the test.

## Fake behavior

- `setSize` clamps the size to `minSize`, as a real app does. A window with `resizable: false` refuses the write.
- `setPosition` and `setSize` add an entry to `writes`. `userMoves` does not.
- `addWindow` puts the window on top, and it makes the window and its app focused. `focus` from the engine does the same.
- `scan` lists the windows of one app. A known window that is not in the fake is gone.
- All windows are on Desktop 1. `currentSpace` always returns 1.

## Limits

These parts are not in `WindowBackend`. A fake backend test cannot control them:

- Desktop machinery: `NativeDesktopController`, `Spaces.list`, `Spaces.of` and `Spaces.move`. Use `virtualWorkspaces = false`.
- AX observers. The engine calls `AXObserverCreate`, which fails for a negative pid. To send a notification, call `manager.handle(_:_:)` with `fake.element(_:)`.
- Mouse state, the mouse warp and `CursorRefresh`. Keep `mouseFollowsFocus` off.
- The focus sink window. A command that focuses an empty display or an empty workspace calls `parkFocus`, which shows a real window. Do not use these commands in a fake backend test.
- Some direct reads of the window server, for example `CGWindowInfo.onScreen()` in `focus(on:)` and in the Overview.
- Template capture and restore.

## Speed

On an Apple M4, a debug build makes a manager in 0.03 ms. Two windows settle in about 2 ms. 200 windows on 20 apps settle in about 0.07 s. A change of layout on these 200 windows uses the main thread for about 2 ms, and for about 8 ms when the full suite runs at the same time. The test `twoHundredWindowsRetileInLessThan50Milliseconds` measures only this main-thread work, because other suites can hold the main actor during a `settle`. It fails if the work takes 50 ms or more.
