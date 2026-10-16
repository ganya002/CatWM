# Button

Button is the one push button: primary, secondary, ghost or danger, in three sizes.

Provide `variant`, `size` (`sm`, default, `lg`), children for the label, optional `icon` (SF Symbol name) with `iconEffect`/`iconTrigger`, and `shortcut` to show its key.

- One `primary` per surface; it carries the ↩ shortcut.
- `ghost` for Skip, Back, Close and other ways out.
- `danger` (on `danger-soft`) only for destructive actions, always with a verb ("Reset Shortcuts").
- Icon-only buttons need `label` and a Tooltip.
