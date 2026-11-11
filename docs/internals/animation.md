# Animation

All animation code lives in `Sources/CatWM/Motion/`, and nothing else may start an animation. `Tools/check-style.sh` enforces this, and a `// style-ok` escape on such a line is itself an error. `App/Perf/FrameRun.swift` may use a display link because it measures frames. The user's animation settings reach every kind of motion through one value, `MotionSpec`, so a setting change moves windows, Desktops and panels alike.

## Window frames

CatWM animates real windows by writing AX frames, so the app's resize and redraw latency still shows in the motion. A display link can pace the writes, but it can't remove that cost. A compositor such as [Hyprland](https://github.com/hyprwm/Hyprland/blob/main/src/render/pass/SurfacePassElement.cpp) fits the client's current buffer to the animated geometry instead. macOS gives a window manager no such hook.

`Animator` steps on an `NSScreen` display link for the fastest display that holds an active destination. Each app writer samples at the link's `targetTimestamp`, or at its estimated write-completion time when it has fallen behind. Pending writes coalesce, so a slow app skips obsolete frames instead of replaying them. The estimate learns only from successful writes: samples are capped at 50 ms, it follows rising costs at 80% weight and falling costs at 40%, and it expires after one second idle. These are tuning heuristics. A successful AX write doesn't prove the app has drawn fresh pixels.

## Lab: resize animation

`lab.resizeAnimation` picks `live` (the default), `snapshot`, `color-fill` or `stream`. The experiments try to hide the app's redraw latency.

**`snapshot`** captures the source windows and the background without them, gives the real windows their destination frames at once, and scales each capture in a click-through panel. It needs Screen Recording and falls back to live AX motion for overlapping, partly visible or changing frames, and when a foreground window crosses the animation bounds, so a scene never paints over another window. Capture adds tens of milliseconds, so it stays opt-in. `Tools/window-resize-probe.sh` checks it against a paused app.

**`color-fill`** keeps the real window live and paints sampled edge colors over the gap between its native frame and the animated outline. Appearances are prepared on a background queue while windows are idle. A cache miss uses normal AX motion, so capture never delays the start of an animation. Shrinking goes through predicted intermediate native sizes, slightly ahead of the outline. Growing keeps native frames inside the viewport, because a fill can cover a gap but can't crop excess content. Within a tick, writes that release space go first, and position and size go in whichever order keeps the intermediate rectangle closest to the source and target union. Without that, a right-aligned tile briefly extends off its display.

The fill samples narrow side bands, a bottom row and the border and alpha outline, and takes the most common color per band to reduce streaks from text. Bottom growth stretches the longest flat color run, which is a guess at which region grows, such as a sidebar. There's no app whitelist. It supports opaque rectangular and rounded windows with a fixed top edge on one display. True transparency would need a different method. `Tools/window-fill-probe.sh` checks the pixels (seams, borders, corners, everything outside the target), not the latency.

**`stream`** keeps a ScreenCaptureKit stream for each visible tiled window and draws each buffer at native size, cropped to the animated outline, with sampled edge colors in the uncovered space. AX writes continue underneath. Streams run at 5 fps while idle and 120 fps while a scene is visible: a static window still delivers complete frames with a full dirty rectangle, so a 120 fps idle stream cost about 35% CPU for two windows. The first fast frame arrives about 40 ms after `show()`, and until then the scene shows the last idle frame. The background is a snapshot, so a scene draws every visible tile, and a tile that doesn't move shows its live buffer at rest. `close()` flushes the transaction so the panel is gone before the next background capture checks for obstructions. It needs Screen Recording and falls back to AX motion like `snapshot`. On macOS 27, native traffic lights can show up as separate windows and block the visibility guard. The handoff follows AX completion, which doesn't prove the app has repainted. `Tools/window-live-probe.sh` checks native pixel size, cropping, stalls and stream cleanup, not latency.

## Trajectory inherits velocity

Restarting a curve from rest when a target changes mid-flight makes the item stop and start again. `Trajectory(…, velocity:)` uses inertialization instead. It adds `carry * u * (1 - u)^2`, where `carry = velocity * duration - (to - from) * slope0` and `u` is normalized time. The term is 0 at both ends, so the motion still starts at `from` and lands on `to`. Its slope is `carry` at the start and 0 at the end, so the speed starts at the carried velocity and the curve's own landing is untouched.

`DesktopMotion` uses this for reversals. It remembers its last value, time and speed, builds the new trajectory from there and shortens the spec in proportion to the remaining distance. A swipe feeds `track(_:)`, so the slide that follows starts at the finger's speed.
