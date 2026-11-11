# Fake backend

`WindowBackend` (`Tiling/Access/WindowBackend.swift`) is the boundary between the tiling engine and macOS. `AXBackend.shared` sends each call to AX, the window server and `NSWorkspace`. `FakeBackend` (`Tests/CatWMTests/Support/FakeBackend.swift`) runs the real engine on in-memory windows and screens, so tests need no permissions, GUI or real apps. Change the fake, run the engine and examine the result. Don't copy engine logic into a test.

Fake pids are negative, so no AX call can reach a real app. `fake.makeManager()` uses the default config text with animation, gaps, warps and Desktops off. `Config.load()` would read and can write the user's config.

Tests wait on the engine, never on time. `Tools/check-style.sh` rejects sleeps and fixed run-loop waits. `settle` repeats scan, refresh and AX writes until a round writes nothing, and it returns `false` after 8 rounds or 10 s. `wait(_:until:)` re-checks on each `onChange` for timer-driven steps, such as the minimum-size check 0.12 s after a placement.

## Limits

These parts aren't behind `WindowBackend`, so a fake test can't drive them:

- Desktop machinery (`NativeDesktopController`, `Spaces`). Use `virtualWorkspaces = false`.
- AX observers. `AXObserverCreate` fails for a negative pid, so send a notification with `manager.handle(_:_:)`.
- The pointer warp and mouse state. `parkFocus`, the grab move and `mouseFollowsFocus` warp it.
- The focus sink window, which `parkFocus` shows when focus moves to an empty display or workspace.
- Some direct window-server reads, such as `CGWindowInfo.onScreen()` in `focus(on:)` and the Overview.
- Template capture and restore.

On an Apple M4 debug build, 200 windows on 20 apps settle in about 0.07 s, and a relayout of them takes about 2 ms of main thread. `twoHundredWindowsRetileInLessThan50Milliseconds` guards that and measures only main-thread work, because other suites can hold the main actor during `settle`.
