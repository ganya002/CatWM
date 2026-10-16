Ouch is a keyboard-first tiling window manager for macOS. Its interface should feel like a good tool: quiet until you reach for it, exact when you do, and always showing the key that would have been faster. This book is the rule set for every surface Ouch draws: the menu bar menu, Settings, onboarding, tips, the HUD.

## Principles

1. **Show the key.** Every command a person can click shows its shortcut on the right, set in `kbd`. Clicking is how people learn the keys, not a replacement for them.
2. **One floating surface.** Menus, tooltips, tips, coach marks, the HUD and the welcome card are all one component, `Surface`, at five densities. A new floating thing gets a density, never a new look.
3. **Two levels, then search.** Menus nest one level, two at most. Anything deeper goes behind the search field that sits at the top of every menu.
4. **No boxes around content.** Content sits on the ground; rows are separated by a `hairline`, never wrapped in a card. Only things that float (menus, tips, tour cards, HUD) and the one content pane get a surface, and they get depth from `shadow-popover` / `shadow-float`, not borders.
5. **Chrome is a wash (after Zen Browser).** Window chrome and sidebars sit on a soft gradient, `linear-gradient(140deg, wash-1, bg 55%, wash-2)`, with items directly on it as pills. The content is one floating rounded pane (`o-pane`, `surface`, 14px radius) inset 8px from the window edge.
6. **Quiet type, one face.** Chillax throughout. 400 for text, 500 for emphasis, 300 for large display; nothing bolder.
7. **Symbols move with meaning.** An SF Symbol effect always reports something: an action landed, a thing refused, the app is busy, a tip is waiting. Never decoration.

## Palette

The system ships one palette, Ouch, with a light and a dark theme (`ouch-light`, `ouch-dark`). It is taken from the app icon: graphite ground, the main window's electric blue as accent, the white windows' cool greys as tint. Hovers are a neutral grey (`hover`); the blue `accent` also marks the current and past tour-step dots. Every component reads semantic tokens only, so a theme is chosen by `data-theme`.

Where a source colour fails contrast it is adjusted only where it carries text, and the raw value stays as a `swatch-*` token: Ouch Light deepens the logo blue `#0a74ff` to `#0a68e6`; Ouch Dark keeps the brighter `#3f95ff` with near-black `on-accent`.

**Colour rules**

- Paint window chrome with the wash (`wash-1` → `bg` → `wash-2`); put the content pane on `surface`; float menus and tips on `surface-raised` (or `glass` where Liquid Glass is unavailable).
- Text is `ink`; secondary text `ink-muted`; placeholders `ink-faint`. Every pair is 4.5:1 or better in both themes.
- Blue is an accent, used sparingly. `accent` fills one thing per view: the primary button, the switch that is on, the current workspace, the progress bar, the selected layout. Its text is `on-accent`. Everything else is neutral: text and symbols in `ink` or `ink-muted`, selection in `hover` or a raised `surface` pill.
- The highlighted or hovered menu row is a `hover` fill; its text keeps its colour. Hover and keyboard highlight never use `accent`. Selected sidebar items are a `surface` pill with `shadow-sm` on the wash.
- Tour cards are plain raised surfaces like every other floating thing; they point with the caret and use a primary button for Next. They are not filled with `accent`.
- `tint` is for shapes only: layout thumbnails, illustrations. Never text. Hovered shapes use `hover` or a neutral grey, never `accent`.
- `success`, `warning`, `danger` always come with a symbol and a word (`checkmark.circle.fill` "Granted", `exclamationmark.triangle.fill` "Safari won't shrink…").
- Focus is a 2px solid `focus` ring, 2px outside the control; it is 3:1 on every surface in every theme.

## Type

Chillax (`--font-sans`, variable 200–700) is the only face, plus SF Mono for keys. Its geometric, slightly soft shapes carry the personality, so weight stays low.

- `display` 44/46 300 for the welcome title and showcase headlines; `numeral` 34 300 in `ink-muted` for step numbers.
- `title` 22/27 400 for tour cards, pane titles (40px 300 in Settings), the HUD. Emphasise one word with `<em>` at 500.
- `heading` 15/20 500, `body` 13.5/19 400, `body-medium` 500, `caption` 12/16, `label` 12/16 500.
- `kbd`, `kicker` (the only uppercase: "STEP 2 OF 6") and `code` in SF Mono.

Labels, captions, buttons, keys and menu rows never wrap: they are single-line, `white-space: nowrap`, truncated with an ellipsis where space runs out. Only body prose wraps; keep it to two lines in floating surfaces.

## Space, radius, size

A 4px grid: `space-0-5` 2, `space-1` 4 … `space-8` 32. Radii nest: the panel radius equals the row radius plus the panel padding (`radius-lg` 12 = `radius-sm` 6 + 6px menu padding), so rows sit concentric inside menus. Rows are `size-row` 30px; controls `size-control` 28px (sm 26, lg 36); small keycaps `size-kbd` 20px, tour keycaps 40px; menus `size-menu` 272px, submenus 232px, the command menu 360px.

## The Surface pattern

One anatomy, five densities. Build anything that floats from it, in this order:

```
head      lead symbol · kicker · (headEnd) · close
title     Chillax title (smaller at sm and md)
body      ink-muted body
keys      large keycaps + live state ("Press it now" → "✓ Nice")
children  rows, menus, groups
actions   dots/spacer · ghost secondary · primary with ↩
progress  3px accent bar
caret     optional, top / bottom / left, pointing at the real target
```

| Density | Used for | Radius | Padding | Shadow |
| --- | --- | --- | --- | --- |
| `xs` | Tooltip (plain raised, like menus) | `radius-md` | 5 × 8 | popover |
| `sm` | Toast, "config reloaded"; the HUD uses 22px | `radius-lg` | 12 × 16 | popover, glass |
| `md` | Menus, submenus, command menu, inline tips | `radius-lg` | 6 | popover |
| `lg` | Coach marks (tour steps), 344px wide | `radius-xl` | 20 × 20 × 16 | float, glass |
| `xl` | Welcome card, 480px wide | 24px | `space-8` | float |

Rules: a tooltip never holds a button; anything with a button is at least `md`. Tour cards (`lg`, plain raised) always point with the caret at the real menu bar item or real window; no full-screen stages, no dimming. Tips after onboarding are `md` with a lead `lightbulb` (`.breathe`), a close button and "No more tips". Nothing inside a surface gets its own box: a permission row inside the welcome card is a Row under a hairline.

## Iconography: SF Symbols

Use SF Symbols only, rendered with `.symbolRenderingMode(.hierarchical)` at the text's weight. SF Symbols can't ship outside Apple platforms, so this web book draws them with Lucide outlines (ISC licence) at 1.75 stroke, keyed by the real symbol name (`data-sf`). In the app always use the real symbol.

| Moment | Symbol | Effect (SwiftUI) |
| --- | --- | --- |
| Menu bar icon while windows animate | `rectangle.split.3x1` | `.symbolEffect(.variableColor.iterative, isActive: animating)` |
| Tiling toggled off/on | `rectangle.split.3x1` ↔ `macwindow.on.rectangle` | `.contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))` |
| Retile, Reload Config | `arrow.triangle.2.circlepath` | `.symbolEffect(.rotate, value: count)` |
| Settings opened | `gearshape` | `.symbolEffect(.rotate.byLayer, value: count)` |
| Update found / tour step passed | `arrow.down.circle`, `checkmark.circle.fill` | `.symbolEffect(.bounce, value:)`, `.transition(.symbolEffect(.appear))` |
| Window refuses to resize | `exclamationmark.triangle.fill` | `.symbolEffect(.wiggle, value:)` |
| Waiting for a key press in the tour | `cursorarrow.rays` | `.symbolEffect(.pulse, isActive:)` |
| Tip available | `lightbulb` | `.symbolEffect(.breathe)` |
| Checkmark in menus, permission granted | `checkmark` | `.symbolEffect(.drawOn, isActive:)` (macOS 26), `.appear` before |
| Menu row hovered | the row's symbol | `.symbolEffect(.scale.up, isActive: hovering)` |
| Layout, Window, Configs, Help | `square.grid.2x2`, `macwindow`, `slider.horizontal.3`, `questionmark.circle` | none, static |

Respect Reduce Motion: indefinite effects stop, discrete ones fall back to `.replace` or none.

## Motion

Two curves: `--ease-out` cubic-bezier(.2,.8,.2,1) for things appearing, `--ease-spring` (SwiftUI `.spring(response: 0.3, dampingFraction: 0.7)`) for things that move under the hand: switch and slider thumbs, segmented thumbs, HUD pop, keycaps. Direct manipulation always follows the pointer exactly, then springs: switches and sliders can be dragged, sliders stretch like rubber past their ends and bump at detents. Durations 120 / 180 / 280 ms. Menus fade and scale from 0.97; submenus slide 4px from their parent.

## Voice

Short, second person, sentence case, no exclamation marks except "Nice". Name the key, not the concept: "Press L to focus the window to the right", not "Use directional focus". Buttons are verbs: "Take the 2-minute tour", "Grant Access", "Got it". Kickers count, never cheer: "STEP 2 OF 6".

## Assets

No logo is included in this system: the app's Dela Gothic One wordmark and icon live in the codebase (`Resources/Icon`). Set the name "Ouch" in plain type here.

