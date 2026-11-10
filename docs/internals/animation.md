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
The estimate learns only from successful native writes. Samples are capped at 50 ms before smoothing;
it follows rising costs with an 80% weight and falling costs with a 40% weight. Recent estimates survive
landing and expire after one second of idle time. These are tuning heuristics, not measured client
repaint times. A successful AX write does not prove fresh pixels are ready.
This paces AX requests; it does not make app redraws or WindowServer presentation atomic.

Compositor-side presentation is a separate mechanism. [Hyprland's surface renderer](https://github.com/hyprwm/Hyprland/blob/main/src/render/pass/SurfacePassElement.cpp)
fits the current client buffer to animated geometry, independently of the client's reported size.
Its [texture coordinates](https://github.com/hyprwm/Hyprland/blob/main/src/render/ElementRenderer.cpp) can crop
or extend edge pixels, so this need not stretch the whole window.
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
animation bounds also uses live AX resizing, so a scene cannot paint over that window.
CatWM's split-handle panels are excluded from these checks and the background capture, so their input regions do not reject adjacent tiles.
Capture preparation currently adds tens of milliseconds on the test Mac. The background inside the hidden real-window footprints is a snapshot;
content outside those footprints remains live. It remains opt-in while capture costs are investigated.

Run `Tools/window-resize-probe.sh` to build a standalone probe from the real capture, scene and clock source.
It creates a disposable app, pauses that app while the snapshot resizes, checks the screenshot pixels at the
animated bounds, resumes the app and changes its content during the animation. It also changes an
unrelated indicator behind the scene and checks that both updates reach the screen. It writes
`/tmp/catwm-resize-stalled.png` and `/tmp/catwm-resize-live.png` and prints `pixel_fit true`,
`resizing_content_live true`, `unrelated_content_live true` and `live_frame_fit true` on success. The probe always resumes and terminates its
child and closes the scene; it does not move user windows.

### Experimental background fills

Set `CATWM_RESIZE_FILL=1` at launch to test color-only fills during tiling. The default is off.
This mode takes precedence over `CATWM_RESIZE_SCENE`; it doesn't enable captured-window compositing.
`Animator` sends presentation samples and cancellations through `WindowPresentation`. `WindowResizeFills`
uses those samples to update the fill against the actual WindowServer frame while AX writes continue.
It closes fills when placement ends, the window is cancelled, or the presentation becomes obstructed.
`AppSurface` prepares appearances on a serial background queue when windows are idle. A cache miss uses
normal AX motion, so capture never blocks the start of an animation. Width-only changes reuse the
prepared vertical color profiles. After placement, the cache is refreshed even during the animation
recovery grace period. A mouse click or display change cancels the current fill. Divider dragging
uses the same presentation path and publishes its desired frames before submitting AX writes.

For a prepared opaque window with a fixed top edge, `ColorFillSizing` uses predicted trajectory sizes
for both shrinking and growing. Shrinking proceeds through intermediate native sizes, slightly ahead
of the visible outline when the writer has learned a lead. Color fills cover the resulting gap around
the smaller real window. Growing native dimensions and predicted positions stay inside the visible
viewport, since a color fill cannot crop excess content. Requests that release
space go first within a tick and a pending per-app batch; different apps still write independently.
Position and size writes use the order that keeps the intermediate rectangle closest to the source
and target union, preventing a right-aligned tile from briefly extending off its display.

Prepare its `WindowFillAppearance` before motion. It samples narrow bands on the left and right,
a row along the bottom, and the native border and alpha outline. It retains color strips and compact
corner masks. Text and controls stay in the real window. There is no app whitelist.

Each side keeps its own colors at the original vertical scale, including browser tabs and toolbars.
The most common color in each sampled band reduces streaks from text and icons. Bottom growth
preserves fixed color regions such as a sidebar by expanding the longest flat color run. This is an
estimate of which region stretches; it doesn't know the app's layout.

A mask keeps the fill inside the desired outline and cuts out live content. The fill covers the old
border and shadow where the window grows, and extends the native border around the desired outline.
Shared corners stay untouched. The masks overlap at their join to avoid an antialiasing gap. Mask
textures use nearest-pixel sampling so a small rectangular mask cannot wash out the live content.
One fixed panel holds the layers. Updates don't capture or resize the panel each frame. Each update reuses one
window-order read for visibility and stacking checks. A fill panel changes its order only when it
opens or the real window rises above it. Its AppKit
appearance animation is disabled so macOS cannot scale the fill away from the live window as it opens.

Run `Tools/window-fill-probe.sh` with existing Screen Recording permission. Use `--light` or `--dark`
to set only the disposable window's appearance. Choose `--style=native`, `--style=browser`,
`--style=sidebar`, or `--style=borderless`. The browser fixture uses live WebKit content with a custom
tab strip and toolbar. The sidebar fixture also checks that the boundary keeps its width after a
partial live resize. `--style=translucent` checks that actual translucent content is left unpainted.
Use `--inspect <window-id> ...` to check appearance preparation on existing app windows without moving them.
Use `--demo` for a persistent interactive browser fixture. Its width and height sliders expose the
color fill, **Catch up** resizes the real window, and **Close** ends the demo and its child process.
This mode doesn't enable fills in the running CatWM or hold the verification lock while you test.

The probes check half-pixel seams, old borders, native corner shapes, titlebar colors, unchanged
content and controls, and every physical pixel outside the target bounds. They also check fractional
targets, retargeting, cancellation and removal when the real window grows and repaints. Images are
saved to `/tmp/catwm-fill-refined-*.png`. These checks verify pixels, not animation latency.
Corner checks compare surface alpha so the source window's external shadow cannot be mistaken for
a change in clipping.

Add `--background` to keep the fixture behind other apps and capture only the test windows through
WindowServer. This mode checks fill-surface opacity at the seams as well as composite pixels. It
excludes WindowServer shadows and doesn't measure physical presentation or latency. Its images use
`/tmp/catwm-fill-background-*.png`. WebKit stays running, so its live pixels may change during the
probe. The browser checks transparency of the helper over the content and controls, and confirms
that WindowServer removes the closed helper. If a covered browser stops presenting fresh content,
the repaint check exits with code 77 and needs a visible run.

The prototype supports opaque rectangular and rounded windows resizing with a fixed top edge on one
display. Predictive native shrinking also requires compatible prepared colors, minimum corner dimensions,
and a matching display scale. The fill hides when native content already covers the viewport, for
vertical moves, or for unsupported geometry. Transparency outside the corner regions is rejected. It cannot crop
another app's excess content or repair stale pixels inside that app's own frame. True transparency
still needs a different method to preserve the backdrop while hiding the real window's shadow.

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
