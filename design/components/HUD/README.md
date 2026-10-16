# HUD

HUD confirms a keyboard action in the middle of the screen: glass Surface with a layout thumbnail and its name.

Provide `layout` (a key of `LayoutThumb.layouts`) or `label`, optional `keys`/`hint`, `warning` for the refuse state, and `pop` (a counter that replays the spring).

- Shown for about a second, never interactive, ignores the mouse.
- The warning variant wiggles `exclamationmark.triangle.fill` and names the app that refused.
