# Kbd

Kbd renders keycaps for a shortcut, a chord, or a sequence of chords.

Provide `keys` (names like `cmd`, `opt`, `shift`, `caps`, `return`, or a letter), optional `then` (further chords, shown with "then"), `size="lg"` for tour keycaps and `pressed` to show the key held down.

- Small keycaps (`size-kbd`, 20px) for hints in tooltips, labels and buttons; menu rows use plain `kbd` text instead.
- Large keycaps (40px, `surface` with a `surface-sunken` lip) only inside coach marks, where the real key press sinks them 2px onto `tint`.
- Order modifiers the macOS way: ⌃ ⌥ ⇧ ⌘, then the key.
