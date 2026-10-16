# Slider

Slider sets a number by dragging, in two shapes: `line` (thin track and thumb) and `bar` (a Control Center style pill whose fill is the indicator).

Provide `min`, `max`, `step`, `value`/`defaultValue`, `onChange`, `label` and `format` (value to display text). Optional: `ticks` (a step number or an array of values; they act as detents), `resetValue` (double-click target, defaults to `defaultValue`), `variant`, `symbol` and `symbolEffect` (bar), `bare` (no label row, value beside the track: for use inside a `Row`) and `width`.

- **Tap to jump, drag to adjust.** A press without moving sends the value to the press point and springs there, in both shapes. Dragging a line follows the pointer; dragging a bar moves relative to where you grabbed it, so grabbing never makes it jump.
- **Smooth under the hand.** While dragging, the fill follows the pointer continuously and only the value rounds to `step`. A bar keeps its size while held: its track darkens a touch, its edge handle grows, and the value pops when it lands on a detent; the icon bounces at either end.
- **No ring on click.** Pressing a slider focuses it without a focus ring, so arrow keys still work; the ring and value bubble show only when focus arrives from the keyboard.
- **Hold ⌥ while dragging** to move at a tenth of the speed for fine values.
- **Detents.** Within 2.5% of a tick the value snaps to it and the thumb gives a small spring bump. Moving to a value springs with a little overshoot, but landing on a tick (by tap or release) eases in without overshoot, so the handle settles exactly on the mark.
- **Rubber band.** Dragging past either end stretches the control a few pixels (and thins it slightly) and springs back on release.
- **Double-click resets** to the default. Arrow keys step (⇧ for ×10), Page Up/Down move a tenth, Home/End jump to the ends.
- While dragging, the line's thumb grows, shows an `accent` core and an inverted value bubble; the bar's label and value switch from `ink` to `on-accent` exactly where the fill passes under them.
- Use `line` inside settings rows and `bar` for a stack of related values (spring bounce, stiffness) where the label belongs inside the control.
