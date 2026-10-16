# Ouch design system

This file is the rule set for every surface that Ouch draws: the menu bar menu, Settings, onboarding, tips and the HUD.

Source: the Ouch design system artifact, https://claude.ai/artifact/GY1GAH7xBUwAzBP1B9mtfY. The artifact has live previews of each component. The values are in code: `Sources/ouch/UI/Theme.swift` (tokens), `Components.swift` and `Popups.swift` (controls). When this file and the code disagree, the code is correct. Update this file.

## Principles

1. **Show the key.** Every command that a person can click shows its shortcut on the right, set in `Kbd` or `kbd` text. Clicking teaches the keys. It does not replace them.
2. **One floating surface.** Menus, tooltips, tips, coach marks, the HUD and the welcome card are one component: `.surface(_ density:)`, at five densities. A new floating thing gets a density, never a new look.
3. **Two levels, then search.** Menus nest one level, two at most. Deeper items go behind the search field at the top of every menu.
4. **No boxes around content.** Content sits on the ground. Hairlines separate rows. Only floating things (menus, tips, tour cards, HUD) and the one content pane get a surface. They get depth from the `popover` and `float` elevations, not from borders.
5. **Chrome is a wash.** Window chrome and sidebars sit on `Theme.wash`: `wash1`, then `bg` at 55%, then `wash2`. Items sit on it as pills. The content is one floating rounded pane (`.pane()`, `surface`, radius 14) inset 8 from the window edge.
6. **Quiet type, one face.** Chillax everywhere. Weight 400 for text, 500 for emphasis, 300 for large display. Nothing bolder, except the wordmark.
7. **Symbols move with meaning.** An SF Symbol effect always reports something: an action landed, a thing refused, the app is busy, a tip is waiting. Never decoration.

## Colour

One palette, `Palette.ouch`, with a light and a dark theme. It comes from the app icon: graphite ground, the electric blue of the main window as accent, the cool greys of the white windows as tint. Components read semantic tokens only.

- Paint window chrome with the wash. Put the content pane on `surface`. Float menus and tips on `surfaceRaised` (or `glass` where Liquid Glass is not available).
- Text is `ink`. Secondary text is `inkMuted`. Placeholders are `inkFaint`. Every pair meets 4.5:1 in both themes.
- Blue is an accent. Use `accent` for one thing per view: the primary button, the switch that is on, the current workspace, the progress bar, the selected layout. Its text is `onAccent`. Everything else is neutral.
- A hovered or highlighted row is a `hover` fill. Its text keeps its colour. Hover and keyboard highlight never use `accent`.
- A selected sidebar item is a `surface` pill with the `sm` elevation, on the wash.
- Tour cards are plain raised surfaces. They are not filled with `accent`.
- `tint` is for shapes only: layout thumbnails and illustrations. Never text.
- `success`, `warning` and `danger` always come with a symbol and a word.
- Focus is a 2 pt `focus` ring, offset 2 pt. It is 3:1 on every surface in every theme.
- `borderControl` is the edge of an interactive control. `hairline` is decorative: never the only edge of a control.

## Type

- `display` 44/46, weight 300. Welcome title and showcase headlines. One per screen.
- `numeral` 34, weight 300, in `inkMuted`. Step numbers.
- `title` 22/27, weight 400. Tour cards, pane titles, the HUD. Emphasise one word at 500.
- `heading` 15/20, weight 500. `body` 13.5/19, weight 400. `body-medium` is `body` at 500. `caption` 12/16. `label` 12/16, weight 500.
- `kbd`, `kicker` and `code` use the mono face. `kicker` is the only uppercase text: "STEP 2 OF 6".

Labels, captions, buttons, keys and menu rows never wrap. They are one line and truncate with an ellipsis (`.oneLine()`). Only body prose wraps. Keep it to two lines in floating surfaces.

## Space, radius and size

- The grid is 4 pt: `Theme.Space` 2, 4, 8, 12, 16, 24, 32.
- Radii nest. The panel radius equals the row radius plus the panel padding: `Radius.lg` 12 = `Radius.sm` 6 + 6 menu padding. Rows sit concentric inside menus.
- Rows are 30 pt (`Theme.rowHeight`). Controls are 28 pt (26 small, 36 large). Small keycaps are 20 pt. Tour keycaps are 40 pt. Menus are 272 pt wide, submenus 232 pt, the command menu 360 pt.

## Surface

`.surface(_ density:, glass:, caret:)` is the one floating container. The parts always appear in this order. Leave a part out. Do not reorder.

```text
head      lead symbol, kicker, trailing item, close
title     Chillax title (smaller at sm and md)
body      inkMuted body
keys      large keycaps and live state ("Press it now", then "Nice")
children  rows, menus, groups
actions   dots or spacer, ghost secondary, primary with the return key
progress  3 pt accent bar
caret     optional: top, bottom or leading, pointing at the real target
```

| Density | Use | Radius | Padding | Elevation |
| --- | --- | --- | --- | --- |
| `xs` | Tooltip | `md` 8 | 5 x 8 | popover |
| `sm` | Toast, "config reloaded" | `lg` 12 | 12 x 16 | float, glass |
| `md` | Menus, submenus, command menu, inline tips | `lg` 12 | 6 | popover |
| `lg` | Coach marks (tour steps), 344 pt wide | `xl` 18 | 20 x 20 x 16 | float, glass |
| `xl` | Welcome card, 480 pt wide | 24 | 32 | float |

Choose the density by job, not by size. A tooltip never holds a button. Anything with a button is `md` or larger. Tour cards always point with the caret at the real menu bar item or real window. They never dim or cover the desktop. Tips after onboarding are `md` with a lead `lightbulb`, a close button and "No more tips". Nothing inside a surface gets its own box.

## Components

Each entry gives the design intent. The Swift type is in brackets.

**Button** [`OButton`, `OIconButton`]. Variants: primary, secondary, ghost, danger, ghostDanger. Sizes: sm, regular, lg.
- One primary per surface. It carries the return key shortcut.
- Use ghost for Skip, Back, Close and other ways out.
- Use danger only for destructive actions, always with a verb ("Reset Shortcuts").
- An icon-only button needs a label and a tooltip.

**Switch** [`OSwitch`, `OSwitchRow`]. Toggles one setting at once. Off is `borderControl` on `surfaceSunken`. On is `accent` with an `onAccent` thumb that springs and stretches while pressed. The thumb follows a drag and springs to the nearer side. For a choice of two to four options, use Segmented.

**Segmented** [`OSegmented`]. Picks one of two to four options with a sliding thumb. For more than four, use a menu submenu or the layout thumbnail grid.

**Slider** [`OSlider`, `OBarSlider`, `OKnob`]. Sets a number by dragging. `OSlider` has a thin track and a thumb. `OBarSlider` is a pill whose fill is the indicator.
- A press without movement jumps to the press point and springs there. A drag on the line follows the pointer. A drag on the bar is relative to the grab point, so it never jumps.
- Only the value rounds to `step`. The fill follows the pointer.
- Hold Option while dragging for a tenth of the speed.
- Within 2.5% of a tick, the value snaps and the thumb gives a small bump.
- Dragging past an end stretches the control a few points, then springs back.
- Double-click resets to `resetValue`. Arrow keys step. Shift gives 10 times the step.
- Pressing with the pointer does not show a focus ring. Focus from the keyboard does.
- Use the line slider inside settings rows. Use the bar for a stack of related values.

**Row and Group** [`ORow`, `OGroup`, `OSectionHeader`, `OPageTitle`]. A row has an optional symbol, a label, a description and a control on the right. A group is an open list with hairlines between rows and no box. Labels are sentence case and name the effect ("Focus follows mouse"). Put units and current values in the description, not the label.

**Kbd** [`Kbd`]. Keycaps for a shortcut, a chord or a sequence. Small keycaps (20 pt) go in tooltips, labels and buttons. Menu rows use plain `kbd` text. Large keycaps (40 pt) go only in coach marks, where the real key press sinks them 2 pt. Order modifiers the macOS way: control, option, shift, command, then the key.

**Tooltip** [`OTooltip`, `Tooltip`]. The smallest surface (`xs`). One short phrase in sentence case, with no full stop. Never a button inside. Every icon-only button gets one. A shortcut is one chord at most. It points at its target with a small caret.

**Menu** [`Popup`, `OMenuRow`, `OMenuButton`, `OMenuPicker`]. A dropdown with groups, checks, radios, switches, inline controls and nested submenus, with type-to-search.
- Nest one level, two at most. Put the current choice of a radio group in the parent row's value.
- Every actionable row shows its shortcut.
- Give hidden aliases to commands that live inside a custom control, so search still finds them.
- Arrow keys, return and escape work. Typing focuses search.

**Command menu**. A menu that opens with the search field first, 360 pt wide. Results group under their top-level parent and show the rest of the path as a breadcrumb. It shares its data with the menu so the two never disagree.

**Coach mark** [`.surface(.lg, caret:)`]. One step of the keyboard tour: step dots, a title, a body, live keycaps and Next. A step completes only when the person presses the real key. Next appears, with the return key, after that. The kicker counts ("STEP 3 OF 6"). The done line is short ("Focus moved").

**HUD**. Confirms a keyboard action in the middle of the screen: a glass surface with a layout thumbnail and its name. Shown for about one second. Never interactive. It ignores the mouse. The warning variant wiggles `exclamationmark.triangle.fill` and names the app that refused.

**Layout picker and thumb** [`LayoutPicker`]. Picks a layout from a grid of thumbnails. The hovered layout's name and description show on one line below. Thumbnails carry no labels, so nothing wraps. Panes are `tint`. The main pane is a darker neutral. A selected main pane is `accent`. Use the app's own layout descriptions as tooltips.

**Workspace strip** [`WorkspaceStrip`]. Workspaces as pills. The current one is `accent` with `onAccent` text. Workspaces with windows are `ink` at 500. Empty ones are `inkFaint` at 400. Both meet 4.5:1.

## Symbols

Use SF Symbols only, at the weight of the text, in hierarchical rendering. Use the real symbol name in the app.

| Moment | Symbol | Effect |
| --- | --- | --- |
| Menu bar icon while windows animate | `rectangle.split.3x1` | `.variableColor.iterative` |
| Tiling toggled off or on | `rectangle.split.3x1` and `macwindow.on.rectangle` | `.replace.magic(fallback: .downUp)` |
| Retile, Reload Config | `arrow.triangle.2.circlepath` | `.rotate` |
| Settings opened | `gearshape` | `.rotate.byLayer` |
| Update found, tour step passed | `arrow.down.circle`, `checkmark.circle.fill` | `.bounce`, `.appear` |
| Window refuses to resize | `exclamationmark.triangle.fill` | `.wiggle` |
| Waiting for a key press in the tour | `cursorarrow.rays` | `.pulse` |
| Tip available | `lightbulb` | `.breathe` |
| Checkmark in menus, permission granted | `checkmark` | `.drawOn` (macOS 26), `.appear` before |
| Menu row hovered | the row's symbol | `.scale.up` |
| Layout, Window, Configs, Help | `square.grid.2x2`, `macwindow`, `slider.horizontal.3`, `questionmark.circle` | none |

- A discrete effect (bounce, wiggle, rotate) reports that something just happened. Bind it to a counter.
- An indefinite effect (pulse, breathe, variable) reports a state that lasts. Stop it when the state ends.
- Use `replace` only for one control that changes state. Do not animate a symbol on every hover, except `scale` in menu rows.
- Respect Reduce Motion. Indefinite effects stop. Discrete effects fall back to `replace` or none.

## Motion

Two curves: `Motion.easeOut` for things that appear, `Motion.spring` for things that move under the hand (switch and slider thumbs, segmented thumbs, the HUD, keycaps). Direct manipulation follows the pointer exactly, then springs. Durations: `Theme.fast` 120 ms, `Theme.medium` 180 ms, `Theme.slow` 280 ms.

## Voice

Short, second person, sentence case. No exclamation marks, except "Nice". Name the key, not the concept: "Press L to focus the window to the right", not "Use directional focus". Buttons are verbs: "Take the 2-minute tour", "Grant Access", "Got it". Kickers count. They never cheer.

## Assets

The app icon and wordmark are in `Resources/Icon` and `Resources/Fonts`. The wordmark uses `Theme.wordmark`.
