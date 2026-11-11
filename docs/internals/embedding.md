# Embedded mode: CatWMKit in a host app

`CatWMKit` is the engine as a static SwiftPM library. The CatWM app links it, and so can another Mac app. A host creates one `CatWMEngine` (`Sources/CatWMKit/Embed/`), gives it a TypeScript config and drives it from Swift. The engine runs in the host's process, so the host owns the GUI, the permissions and the process. `Examples/EmbedHost/` is a minimal host. The host can't be sandboxed, because a sandboxed app can't use Accessibility.

`CatWMEngine` calls the command registry and event bus directly, with no socket or JSON text, but `perform` keeps the access checks. `EngineSurface` is the `TilingSurface` that draws nothing.

The engine name (by default `embed-` plus the host's bundle ID, cut to 24 characters) picks named-instance folders (`control.md`). So it never touches the user's CatWM files, and it ignores every `CATWM_*` variable.

## Features

Every `features` leaf is off until the config turns it on, and an off leaf starts nothing: no observers, taps, scans or socket. `Config.embedded` is the starting value. `presentation` and `input.cursorActions` draw GUI, so a config that turns one on fails with a diagnostic. `WindowManager.effective` forces the options of an off leaf off, so a config change can stop a subsystem through the normal `apply`.

## The host's process

One engine runs per process. A first config that fails starts nothing. A later broken change keeps the last good config. `stop` removes every tap, monitor, observer and watch, puts parked windows back and ends the event streams, so a host must call it before it quits. `setOption` overrides stay in memory, and the host saves them through `overrides`.

The library never sets the activation policy or main menu, terminates the app, installs signal handlers, stops other instances or asks for a permission. The Desktop slide needs a guard process, which is a second run of the executable, so embedded mode switches Desktops with the macOS swipe instead (`NativeDesktopController.guarded`).

With a `scope`, the engine writes the same scope claim as a scoped instance, so the user's CatWM leaves those pids alone.
