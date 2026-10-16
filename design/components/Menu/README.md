# Menu

Menu is the dropdown with groups, checks, radios, switches, inline controls and nested submenus, plus type-to-search.

Provide `items`: each `{type, id, label, symbol, shortcut, value, checked, group, danger, disabled, items, render, keywords, hidden}` where `type` is `item`, `check`, `radio`, `switch`, `sub`, `label`, `sep`, `custom`, `footer` or `search`. Optional `glass`, `onSelect`, and for static previews `openIndex`, `highlight`, `query`.

- Nest one level, two at most; put the current choice of a radio group in the parent row's `value`.
- Every actionable row shows its shortcut. Give hidden aliases (`hidden: true`) to commands that live inside a custom control so search still finds them.
- Hover opens after 100 ms with a 180 ms grace period; ↑↓ → ← ↩ esc work; typing focuses search.
- `Ouch.ouchMenu()` returns the real menu bar menu as data.
