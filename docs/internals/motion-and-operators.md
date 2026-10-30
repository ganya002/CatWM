# Motions and operators

A directional bind has two parts. The key is the motion: `h j k l` name a direction. The modifier is the operator: no modifier focuses, `Shift` moves. This is the same idea as Vim, where a motion produces a target and an operator acts on it.

```
bind = ,      j, movefocus,  d     # operator: focus   motion: down
bind = SHIFT, j, movewindow, d     # operator: move    motion: down
```

The code is in `Tiling/Navigation/`:

- `Motion/` turns a direction into a target. It does not change any state.
- `Operator/` takes a target and does one action. It never searches for a neighbor.

## Why one resolver

Before this change, `moveFocus` and `moveWindow` each found their own neighbor. Focus wrapped at the edge of the layout. Move did not. A new operator would have needed a third copy of the rules, and each copy could drift.

Now `WindowManager.resolve` is the only place with motion rules. Every operator calls it. A new operator needs no direction logic. A change to a rule applies to all operators at once.

## Vim comparison

Vim keeps three things separate: the key table, motions that move the cursor, and `do_pending_operator()`, which applies an operator to the range a motion produced. CatWM copies only the split between motion and operator.

CatWM does not copy the key sequence (`d` then `w`). The modifier is held with the key, so `Hotkeys.match` stays a stateless table lookup. A pending-operator state would add counts, timeouts and a stuck-state risk. The hot path of an event tap that handles every key press must stay simple and fast. The chord gives the same composition without that cost.

## Resolver rules

`MotionResolver` holds the pure geometry. `resolve` applies the rules in this order and stops at the first match:

1. **CatWM fullscreen.** A fullscreen window has no spatial neighbor. The resolver cycles through the tiled windows on its screen. Left and up go back. Right and down go forward.
2. **Neighbor.** The nearest window in that direction on any screen. Windows that overlap on the other axis rank first. Among windows at the same edge, the most recently focused one wins.
3. **Monitor.** The next monitor in that direction.
4. **Wrap.** The far end of the row or column on the current screen. If all windows share one frame (a stack), cycle through the stack.

### Why wrap comes last

If wrap came before the monitor rule, a window at the bottom of the upper monitor would wrap in place. It could never reach the monitor below. Neighbor and monitor come first, so wrap acts only on an edge of the whole display arrangement.

### Why a new monitor rule

The old `screen(from:spec:in:)` compares only the centers of screens. A monitor beside the current one, at a different height, then counts as "below". That breaks vertical wrap on a laptop with an external display.

The resolver uses a stricter rule. The monitor must start at or past the edge in that direction. It must also overlap on the other axis. `focusmonitor` and `movewindowtomonitor` still use the old function, because they work with a named monitor and not with a direction.

### Behavior of a monitor target

- A monitor target with a visible window in it is already found by rule 2, so rule 3 acts only when the monitor is empty.
- Focus moves to the topmost window of that monitor, or parks focus there.
- Move assigns the window to the workspace shown on that monitor.

## Operators

| Operator | Dispatcher | Window target | Monitor target |
|---|---|---|---|
| Focus | `movefocus` | focus the window | focus the monitor |
| Move | `movewindow`, `swapwindow` | swap order with it | assign to its workspace |

Move uses `swapOrder`, so it is a swap and not a rotation. At the bottom edge, the moved window and the top window exchange places. Floating windows are never moved.

`moveFocus` and `moveWindow` stay as thin callers on `WindowManager`. Dispatch, the onboarding lessons and the CLI call them, and their names did not change. The dispatcher names, the config syntax and the `mon:` argument are the same as before.

## Focus echo after a swap

Some apps make themselves frontmost when CatWM moves their window. We saw this with tldraw: about 10 ms after a swap, tldraw became frontmost. CatWM read this as a user switch, dropped the pending focus, and the next press moved the wrong window. Wrap did not cause this. A plain neighbor swap shows the same trace.

After a swap with a window of another app, `move` stores a `FocusEcho` for 0.4 s. It holds the moved window and the pid of the other app. If that app activates in that time, the activation observer in `WindowManager+start.swift` focuses the moved window again and skips the normal handling. An activation of any other app, or an activation after 0.4 s, is handled as before.

## Add an operator

1. Add a file in `Operator/` with an extension on `WindowManager`.
2. Call `resolve(_:from:among:)` to get the `MotionTarget`.
3. Act on `.window` and `.monitor`. Do not write any neighbor or wrap logic.
4. Add a `WindowAction` in `Actions/` and register it in `WindowActions.all`. See [Add a command](control.md#add-a-command) for the dispatcher steps.

## Add a motion

Add a case to the rules in `MotionResolver` and to `resolve`. Every operator then supports it. Add a test in `MotionResolverTests`.

## What we did not do

- **No `Target` rename for generic use.** The type is `MotionTarget`, because `Target` is too general for a global name.
- **No operator setting or config syntax.** Users do not name operators. The modifier choice is the whole interface.
- **No changes to `focusmonitor` and `movewindowtomonitor`.** They have a different input and no reported fault.

## Tests

`Tests/CatWMTests/MotionResolverTests.swift` covers: a neighbor in each direction, a monitor before wrap in both vertical directions, an offset monitor that does not block wrap, wrap in all four directions, and a stack cycle.

The tests check the pure rules. The live behavior with real windows and several monitors needs a manual test.
