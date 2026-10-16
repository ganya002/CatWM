# Tooltip

Tooltip is the smallest Surface: a plain raised label, the same surface as menus, with an optional shortcut.

Wrap the target as children; provide `label`, optional `keys`/`then`, `side` (`bottom`, `top`, `right`) and `delay` (500 ms default). `open` forces it visible.

- One short phrase in sentence case, no full stop. Never a button inside: use a tip (Surface `md`).
- Every icon-only button gets one.
- All tooltips share one height (28px), padding (5 × 8) and type. A shortcut is one chord at most; a sequence belongs in a tip.
- A tooltip always points at its target with a small caret, centred on the side it opens from.
- It uses the same pointer as every other surface: the rounded diamond, no extra border. Depth comes from the shared popover shadow.
