# Animation

All animation code lives in `Sources/CatWM/Motion/`. Nothing else may start an animation. `Tools/check-style.sh` rejects `NSAnimationContext`, `.animator()`, `CABasicAnimation` and the other `CA*Animation` types, `CADisplayLink`, a `Timer` under 0.1 s, raw SwiftUI curves (`.easeOut(`, `.spring(`, `.snappy`, `Animation(` and so on), and a `withAnimation(` or `.animation(` whose argument is not a `Motion.*` token or `nil`. A `// style-ok` comment on such a line is itself an error. `App/Perf/FrameRun.swift` may use a display link because it measures frames.

The user's animation settings (duration, curve, bounce, on or off) reach every kind of motion through one value, `MotionSpec`, so a setting change moves windows, Desktops and panels alike.

## Folders

- `Engine/`: `AnimationCurve` (the curve maths), `MotionSpec` (duration, curve and bounce, read from `Config` with `MotionSpec(config)`, or `.instant`) and `Trajectory` (one number moving along the curve).
- `Windows/`: window frames at 120 Hz. `Animator` steps the frames, `AXWriter` is the per-app AX write queue, `FollowedMoves` and `CursorRefresh` keep the pointer and followers in step, `MotionStats` records frame timing.
- `Desktop/`: `DesktopMotion`, the display-link driver of the Desktop slide.
- `Kit/`: `Motion.swift` holds the SwiftUI tokens (`Motion.easeOut`, `Motion.spring`, `Motion.fade` and others). `MotionKit.swift` holds the AppKit helpers `Motion.group`, `Motion.fade(_:to:)` and `PanelGlide`.

## Animate each kind of thing

A window frame, with the user's settings:

```swift
animator.animate(moves, spec: MotionSpec(config))
```

`WindowManager` owns the one `Animator`. A new `animate` call for a window that is still moving starts from its current frame and speed.

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
