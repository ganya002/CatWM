# Radiant jade — Ouch redesign spec

Paper file: **Radiant jade** (`01M4THC5Y976855W5RC7NYK784`)

Built so far:

- `A · Quiet Instrument — Jade (own)`: light, shadcn-style. Command menu with a flyout submenu, Settings → Gaps & padding, tooltip, tour coachmark, permission card, layout HUD, window-mode bar.
- `B · Night Console — Jade (own)`: dark, power-user. Menu that drills in as stacked sheets with a layout grid, Settings → Keyboard with a nested row-actions menu and a config diff footer, hint docked to a window, permission stepper, HUD pill, toast, mode bar.
- `System · Sheet pattern, flow & symbols`: intro, 01 Anatomy, 02 Size ladder. **Sections 03–05 below still need to go on the canvas.**

## The pattern: one Sheet

Every surface is a Sheet: **Header** (animated symbol · title/search/breadcrumb · shortcut) → **Rows** → **Footer** (key hints or actions).

Rows use four fixed lanes: symbol 18 · label (flex) · meta · accessory 44 (key / chevron / switch / badge). Rows are 32pt in menus and 52pt in Settings.

| Size  | Used for                          | Width        | Radius | Dismiss              |
|-------|-----------------------------------|--------------|--------|----------------------|
| xs    | Tooltip, setting hint             | ≤ 260        | 9      | pointer leaves       |
| sm    | Command menu, submenu, row actions| 220–356      | 10–12  | esc · click out      |
| md    | Tour step, toast, docked hint     | 330–360      | 12     | done · esc skip      |
| lg    | Welcome, permission, confirm      | 356–420      | 14     | explicit only        |
| glyph | Layout HUD                        | 196 sq / pill| 22/full| auto · 900ms         |
| bar   | Submap mode (`-- WINDOW --`)      | hug          | 10/full| leaves with the mode |

## 03 · Menu flow

1. Click the status item or press **⌥ Space** to open the root Sheet. It has search, a **Now** strip (display · workspace · inline layout switcher), a **Workspaces** strip (1–0, dots = window count), and groups (Windows / Ouch).
2. **→** or **↵** on a row with a chevron opens its level:
   - **A, flyout:** the submenu opens to the side, lined up with the row, with a breadcrumb header.
   - **B, drill-in:** the new level replaces the panel. The parent peeks behind it as a stacked card, and the breadcrumb chips are clickable.
3. **↵** applies. A HUD (glyph/pill) confirms what changed and what it was before ("was BSP").
4. **⌫ / ←** goes up one level, **esc** closes everything.

Rules: at most 2 levels deep · every level can be searched from the root · every row shows its shortcut · the Settings row menus (⋯) use the same Sheet and the same keys.

## 04 · SF Symbols (power-user states)

| Surface | Symbol | Effect | Trigger |
|---|---|---|---|
| Status item | layout glyph (`rectangle.split.2x1`, `square.grid.2x2`, …) | `.contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))` | layout changes |
| Status item, window mode | `keyboard` | `.symbolEffect(.breathe.pulse, isActive: inSubmap)` | submap entered |
| Retile row | `arrow.clockwise` | `.symbolEffect(.rotate.byLayer, value: retileCount)` | retile |
| Tiling toggle | `square.grid.2x2` ↔ `square.dashed` | `.replace.offUp` | toggled |
| Workspace switch | `2.square` → `3.square` | `.replace.downUp` (direction follows the number) | workspace changes |
| Reload config | `doc.badge.gearshape` | `.bounce.up` on success; `exclamationmark.triangle` + `.wiggle` on warning | reload |
| Permission, waiting | `lock.shield` | `.pulse.wholeSymbol` (repeating) → `.replace` to `checkmark.shield.fill` | AX granted |
| Update | `arrow.down.circle` | `.variableColor.iterative` while downloading → `.drawOn` when ready | Sparkle state |
| Tour progress | `circle.dotted` / `circle` | `variableValue` = step / total | each step |
| Tour hint, focus | `arrow.left.to.line` etc. | `.wiggle.left` / `.wiggle.right` matching the direction | step shown |
| Bind recording | `record.circle` | `.breathe` while listening, `.bounce` on capture | record keys |
| Conflict | `exclamationmark.triangle` | `.wiggle` once | conflict found |
| Settings gear | `gearshape` | `.rotate` on hover | hover |
| Sidebar icons | — | `.symbolRenderingMode(.hierarchical)`; active row `.palette(accent, secondary)` | selection |

Keep motion meaningful: one effect per event, never loop decoration. Respect Reduce Motion: replace `.rotate`/`.wiggle` with `.replace` or nothing.

## 05 · Palettes (literal → token mapping for duplicating boards)

Source literals in A: surface `#FFFFFF`, wash `#F4F6F5`, line `#E3E8E6`, ink `#16201C`, muted `#5E6B66`, faint `#8E9A95`, accent `#2F8F6B`, accent-soft `#E2F0EA`, desk `#DCE4E0`, accent-on-dark `#5FD3A4`.
Source literals in B: ground `#0B0E0D`, surface `#141817`, raised `#1B201F`, line `#262C2A`, line-strong `#3A413F`, ink `#E8EEEC`, muted `#8A9893`, faint `#5C6864`, accent `#5FD3A4`, accent-soft `#1A3A2F`.

| Role | P1 Baltic · A | P1 · B | P2 Strawberry · A | P2 · B | P3 Gunmetal · A | P3 · B |
|---|---|---|---|---|---|---|
| desk / ground | `#BBCDE5` | `#161616` | `#EFDCD7` | `#1E1E24` | `#C6C5B9` | `#2B2E30` |
| surface | `#FFFFFF` | `#222222` | `#FFFFFF` | `#26262D` | `#FDFDFF` | `#393D3F` |
| wash / raised | `#F3F6FA` | `#2A2D31` | `#F7EBE8` | `#2E2E36` | `#F3F3EF` | `#43484A` |
| line | `#DCE5F1` | `#353A40` | `#EBDDD9` | `#3A3A42` | `#E1E0D8` | `#4E5457` |
| ink | `#222222` | `#F2F5F9` | `#1E1E24` | `#F7EBE8` | `#393D3F` | `#FDFDFF` |
| muted | `#5B6470` | `#9AA6B4` | `#444140` | `#A89F9C` | `#546A7B` | `#C6C5B9` |
| faint | `#8C96A3` | `#66707C` | `#8A817E` | `#6E6866` | `#8E9396` | `#8A8F91` |
| accent | `#1C5D99` | `#BBCDE5` | `#E54B4B` | `#FFA987` | `#4E7A85`* | `#7FB0BC` |
| accent-soft | `#E3ECF6` | `#1C5D99` @ 35% | `#FCE3DE` | `#4A2E2A` | `#E4EEF0` | `#2F4A51` |
| accent-on-dark | `#639FAB` | — | `#FFA987` | — | `#62929E` | — |

\* `#62929E` (pacific cyan) is only about 3.4:1 on white. Use it for fills and switches, and the darker `#4E7A85` for accent text.
P2 · B keeps strawberry `#E54B4B` for destructive rows ("Remove bind") and tangerine as the accent.

## Still to do in Paper (after the limit resets)

1. System board: add sections 03 (flow diagram), 04 (symbol table, with frame-by-frame states) and 05 (swatches).
2. Duplicate A and B three times. On each copy, run `find_nodes` per source literal, then `update_styles` with the mapping above.
3. Restart Paper so it sees the installed Fontshare fonts, then swap `Instrument Serif` → **Zodiak** (A) and `Space Grotesk` → **Chillax** (B). Body stays SF Pro (Inter stands in for it on the canvas).
