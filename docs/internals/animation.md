# Animation

All animation code lives in `Sources/CatWM/Motion/`. Nothing else may start an animation. `Tools/check-style.sh` rejects `NSAnimationContext`, `.animator()`, `CABasicAnimation` and the other `CA*Animation` types, `CADisplayLink`, a `Timer` under 0.1 s, raw SwiftUI curves (`.easeOut(`, `.spring(`, `.snappy`, `Animation(` and so on), and a `withAnimation(` or `.animation(` whose argument is not a `Motion.*` token or `nil`. A `// style-ok` comment on such a line is itself an error. `App/Perf/FrameRun.swift` may use a display link because it measures frames.

The user's animation settings (duration, curve, bounce, on or off) reach every kind of motion through one value, `MotionSpec`, so a setting change moves windows, Desktops and panels alike.

## Folders

- `Engine/`: `AnimationCurve` (the curve maths), `MotionSpec` (duration, curve and bounce, read from `Config` with `MotionSpec(config)`, or `.instant`) and `Trajectory` (one number moving along the curve).
- `Windows/`: window frames paced by a display link. `Animator` steps the frames, `AXWriter` is the per-app AX write queue, `FollowedMoves` and `CursorRefresh` keep the pointer and followers in step, `MotionStats` records frame timing.
- `Desktop/`: `DesktopMotion`, the display-link driver of the Desktop slide.
- `Kit/`: `Motion.swift` holds the SwiftUI tokens (`Motion.easeOut`, `Motion.spring`, `Motion.fade` and others). `MotionKit.swift` holds the AppKit helpers `Motion.group`, `Motion.fade(_:to:)` and `PanelGlide`.

## Animate each kind of thing

A window frame, with the user's settings:

```swift
animator.animate(moves, spec: MotionSpec(config))
```

`WindowManager` owns the one `Animator`. A new `animate` call for a window that is still moving starts from its current frame and speed.

Window animation uses an `NSScreen` display link for the fastest display containing an active destination.
`WindowFrameClock` sends its `targetTimestamp` to `Animator`; each app writer samples at that deadline,
or at its estimated write-completion time if it has already fallen behind. Pending writes are coalesced,
so a slow app skips obsolete frames instead of replaying them. The link stops when no trajectories remain.
This paces AX requests; it does not make app redraws or WindowServer presentation atomic.

Compositor-side scaling is a separate mechanism. [Hyprland's surface renderer](https://github.com/hyprwm/Hyprland/blob/main/src/render/pass/SurfacePassElement.cpp)
scales the client buffer to the current animated geometry, independently of the client's reported size.
CatWM normally interpolates real AX window frames, so client resize and redraw latency still affect motion.
A display link cannot remove that cost.

### Experimental resize scenes

Start a named instance with `CATWM_RESIZE_SCENE=1` to enable snapshot compositing. `AppSurface` installs the
capture factory on `Animator`. `WindowSceneCapture` captures the visible source windows and the background
without those windows. `WindowResizeScene` draws the background and scales each captured window independently
inside a click-through `CatWMPanel`. Its layer rectangles use unrounded trajectory samples; AX writes still
use pixel-aligned frames. This keeps the visible buffer fitted even when the app is late or stopped.

The real windows stay on their Desktop and receive their destination frames at the start. Their layers
animate independently; the apps no longer resize for every animation frame. A masked background covers
the real windows and any intermediate size/position combinations until placement is confirmed. The rest
of the scene is transparent, so unrelated windows keep updating. Window textures refresh off the main
thread, with at most one capture in flight for each window. New buffers are fitted to the current animated
rectangle when they arrive. The panels close after all trajectories and landing writes finish. A mouse click, display change, cancellation or an
instant move closes the scene too. Retargeting keeps the scene when the same captured windows and displays
can represent the new targets; otherwise it returns to live AX animation.

This path runs only with existing Screen Recording permission. Overlapping, partially
visible or changing source frames return to live AX animation. A foreground window intersecting the
animation bounds also uses live AX resizing, so a scene cannot paint over that window. Capture preparation currently adds tens of
milliseconds on the test Mac. The background inside the hidden real-window footprints is a snapshot;
content outside those footprints remains live. It remains opt-in while capture costs are investigated.

Run `Tools/window-resize-probe.sh` to build a standalone probe from the real capture, scene and clock source.
It creates a disposable app, pauses that app while the snapshot resizes, checks the screenshot pixels at the
animated bounds, resumes the app and changes its content during the animation. It also changes an
unrelated indicator behind the scene and checks that both updates reach the screen. It writes
`/tmp/catwm-resize-stalled.png` and `/tmp/catwm-resize-live.png` and prints `pixel_fit true`,
`resizing_content_live true`, `unrelated_content_live true` and `live_frame_fit true` on success. The probe always resumes and terminates its
child and closes the scene; it does not move user windows.

One number, for example a scroll offset or a slider, stepped by your own clock:

```swift
let track = Trajectory(from: a, to: b, spec: spec)
let value = track.value(at: elapsed)
// Retarget: carry the current speed into the new trajectory.
let next = Trajectory(from: value, to: c, spec: spec, velocity: track.velocity(at: elapsed))
```

A Desktop slide: `DesktopMotion.animate(from:to:with:update:)` calls `update` once per display frame. `NativeDesktopController` is the only caller.

A panel frame:

```swift
let glide = PanelGlide()          // keep one for each panel
glide.to(frame, on: panel, spec: spec)
```

A window fade:

```swift
Motion.fade(panel, to: 0) { panel.orderOut(nil) }
```

AppKit property changes that should run as one timed group:

```swift
Motion.group(Theme.medium) { view.animator().alphaValue = 1 }
```

SwiftUI:

```swift
.animation(Motion.easeOut, value: isShown)
withAnimation(reduceMotion ? Motion.fade : Motion.spring) { picked = option }
```

## Why Trajectory inherits velocity

When a motion reverses or a new target arrives mid-flight, restarting the curve from rest makes the item stop and start again. A `Trajectory` created with `velocity:` leaves at that speed instead.

The method is inertialization. The curve's own start slope is replaced by the carried velocity. `carry = velocity * duration - (to - from) * slope0` is the difference between the two start slopes, and it is added as `carry * u * (1 - u)^2`, with `u` the normalized time. That term is 0 at `u = 0` and `u = 1`, so the position starts at `from` and still lands exactly on `to`. Its slope is `carry` at `u = 0` and 0 at `u = 1`, so the speed starts at the carried velocity and the curve's own end speed is untouched. Position and speed are continuous at the join, and the difference decays smoothly to nothing.

## Desktop reversal

`DesktopMotion` remembers the last value it sent, its time and its speed. A new `animate` call reads that sample, builds a `Trajectory` from the current value to the new target with the speed as `velocity`, and shortens the spec in proportion to the remaining distance. A reversal in mid-slide turns around smoothly. A swipe gesture feeds `track(_:)` with the finger position, so the slide that follows starts at the finger's speed.

## Add a token or a helper

Add a SwiftUI token as a `static let` (or a function with a `reduce` parameter, like `Motion.snap(_:)`) in `Motion/Kit/Motion.swift`. Take durations from `Theme.fast`, `Theme.medium` and `Theme.slow`. Show it on the Motion page of the Design Gallery if it is new.

Add an AppKit helper in `Motion/Kit/MotionKit.swift`. A new kind of window or frame motion goes in `Motion/Windows/` or `Motion/Desktop/` and takes a `MotionSpec`. Do not call the raw API at the call site, and do not add a `style-ok`.
