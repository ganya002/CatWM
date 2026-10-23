# CatWM design system

This file is the rule set for every surface that CatWM draws: the menu bar menu, Settings, onboarding, tips and the HUD.

Source: the CatWM design system artifact, https://claude.ai/artifact/GY1GAH7xBUwAzBP1B9mtfY.

## Visual reference and editing

The Design Gallery is the visual reference. It draws every token and component with the real Swift code, so it cannot differ from the app. It is in debug builds only (`Sources/ouch/UI/Gallery/`). Build and open it:

```text
./build.sh --dev
open build/ouch.app --args --gallery
```

The Appearance control at the top switches between system, light and dark. When you add or change a component, add or change its example in the component’s own file. The build collects `GalleryExample` registrations. To get a picture without a window, run the test with `OUCH_GALLERY_PNG=/path/to/gallery.png swift test`.

A change to a token or a component rule is not finished until `Sources/ouch/UI/Theme/`, the matching file in `UI/Components/`, the gallery and this file agree with it.

## Principles

1. **Show the key.** Every command that a person can click shows its shortcut on the right, set in `Kbd` or `kbd` text. Clicking teaches the keys. It does not replace them.
2. **One floating surface.** Menus, tooltips, tips, coach marks, the HUD and the welcome card are one component: `.surface(_ density:)`, at five densities. A new floating thing gets a density, never a new look.
3. **Two levels, then search.** Menus nest one level, two at most. Deeper items go behind the search field at the top of every menu.
4. **Containers nest twice, then stop.** In Settings the content pane is one `surface` container on the ground, and each group of rows is one `surfaceRaised` container inside it (`OGroup`). Hairlines separate the rows inside a group. Nothing else gets a box. Floating things (menus, tips, tour cards, HUD) get depth from the `popover` and `float` elevations, not from borders.
5. **Chrome is flat.** Window chrome and the Settings rail sit on `Theme.wash`, which is flat: `wash1` and `wash2` equal `background`, black in the dark theme and white in the light theme. Items sit on it as pills. The content is one rounded pane without a shadow (`.pane(shadow: false)`, `surface`, radius 14), inset 10 pt on the top, bottom and trailing sides.
6. **Two faces.** Pilcrow Rounded for the wordmark, display, titles, headings and keycaps: Bold for the wordmark and display, Semibold for the rest. The system font for body text, labels, captions and menu rows. Nothing else.
7. **Symbols move with meaning.** An SF Symbol effect always reports something: an action landed, a thing refused, the app is busy, a tip is waiting. Never decoration.

## Colour

One palette, `Palette.catwm`, with a light and a dark theme. It comes from the CatWM brand: a black ground with white type in the dark theme, a white ground with black type in the light theme, and sky as the one accent. The four brand hues (sky, lemon, magenta, lime) are for the website and the brand sheet. Only sky enters the app. Components read semantic tokens only.

- Paint window chrome with `background`. Put the content pane on `surface`. Float menus, dropdowns and tips on `surfaceRaised`, flat, with the `popover` elevation. Only the HUD uses glass.
- Text is `ink`. Secondary text is `inkMuted`. Placeholders are `inkFaint`. Every pair meets 4.5:1 in both themes.
- Sky is the accent. Use `accent` for one thing per view: the primary button, the switch that is on, the current workspace, the progress bar, the selected layout, a drop target. Its text is `onAccent`, black in both themes. Accent-coloured text uses `accentInk`, which is darker in the light theme so it meets 4.5:1. Everything else is neutral: row symbols, step numbers, workspace numbers in the overview, group titles and page titles are `ink` or `inkMuted`. A selected pill (a rail page, a modifier layer in the shortcut map) is `ink` with `background` text, never `accent`.
- A hovered or highlighted row is a `hover` fill. Its text keeps its colour. Hover and keyboard highlight never use `accent`.
- A selected rail item is an `ink` pill with `background` text: white on black in the dark theme, black on white in the light theme. Other items are `inkMuted` text and get a `surface` pill on hover. Rail items have no symbols.
- Tour cards are plain raised surfaces. They are not filled with `accent`.
- `tint` is for shapes only: layout thumbnails and illustrations. Never text.
- `success`, `warning` and `danger` always come with a symbol and a word.
- Focus is a 2 pt `focus` ring, offset 2 pt. It is 3:1 on every surface in every theme.
- `borderControl` is the edge of an interactive control. `hairline` is decorative: never the only edge of a control.

## Type

- `wordmark` Pilcrow Rounded Bold, tracking -0.03 em. `Theme.wordmark`.
- `display` 44/48, Pilcrow Rounded Bold. Welcome title and showcase headlines. One per screen.
- `numeral` 34, weight 300, in `inkMuted`. Step numbers.
- `title` 22/27, Pilcrow Rounded Semibold. Tour cards, pane titles, the HUD.
- `heading` 15/20, Pilcrow Rounded Semibold. Group titles in Settings (`sectionTitle`) use it in `ink`. `body` 13.5/19, system font at 400. `body-medium` is `body` at 500. `caption` 12/16. `label` 12/16, weight 500.
- `kbd` is Pilcrow Rounded Semibold through `Theme.keys`. The face has no modifier glyphs, so the font cascades to the system font for ⌘ ⇧ ⌥ ⌃ ⇥ ↩. `kicker` is Pilcrow Rounded Semibold 12 in `inkMuted`, tracking 0.05 em, and the only uppercase text: "STEP 2 OF 6". `code` uses the mono face.

Labels, captions, buttons, keys and menu rows never wrap. They are one line and truncate with an ellipsis (`.oneLine()`). Only body prose wraps. Keep it to two lines in floating surfaces.

## Space, radius and size

- The grid is 4 pt: `Theme.Space` 2, 4, 8, 12, 16, 24, 32.
- Radii nest. The panel radius equals the row radius plus the panel padding: `Radius.large` 12 = `Radius.small` 6 + 6 menu padding. Rows sit concentric inside menus.
- Rows are 30 pt (`Theme.rowHeight`). Settings rows are at least 44 pt. Controls are 28 pt (26 small, 36 large). Small keycaps are 20 pt, medium 30 pt, tour keycaps 40 pt. Menus are 272 pt wide, submenus 232 pt, the command menu 360 pt.

## Surface

`.surface(_ density:, glass:, caret:)` is the one floating container. The parts always appear in this order. Leave a part out. Do not reorder.

```text
head      lead symbol, kicker, trailing item, close
title     title in Pilcrow Rounded Semibold (smaller at small and medium)
body      inkMuted body
keys      large keycaps and live state ("Press it now", then "Nice")
children  rows, menus, groups
actions   dots or spacer, ghost secondary, primary with the return key
progress  3 pt accent bar
caret     optional: top, bottom or leading, pointing at the real target
```

| Density | Use | Radius | Padding | Elevation |
| --- | --- | --- | --- | --- |
| `extraSmall` | Tooltip | `medium` 8 | 5 x 8 | popover |
| `small` | Toast, "config reloaded" | `large` 12 | 12 x 16 | float, glass |
| `medium` | Menus, submenus, command menu, inline tips | `large` 12 | 6 | popover |
| `large` | Coach marks (tour steps), 344 pt wide | `extraLarge` 18 | 20 x 20 x 16 | float, glass |
| `extraLarge` | Welcome card, 480 pt wide | 24 | 32 | float |

Choose the density by job, not by size. A tooltip never holds a button. Anything with a button is `medium` or larger. Tour cards always point with the caret at the real menu bar item or real window. They never dim or cover the desktop. Tips after onboarding are `medium` with a lead `lightbulb`, a close button and "No more tips". Nothing inside a surface gets its own box.

## Components

Each entry gives the design intent. The Swift type is in brackets.

**Button** [`OButton`, `OIconButton`]. Variants: primary, secondary, ghost, danger, ghostDanger. Sizes: small, regular, large.
- One primary per surface. It carries the return key shortcut.
- Use ghost for Skip, Back, Close and other ways out.
- Use danger only for destructive actions, always with a verb ("Reset Shortcuts").
- An icon-only button needs a label and a tooltip.

**Switch** [`OSwitch`, `OSwitchRow`]. Toggles one setting at once. Off is `borderControl` on `surfaceSunken`. On is `accent` with an `onAccent` thumb that springs and stretches while pressed. The thumb follows a drag and springs to the nearer side. For a choice of two to four options, use Segmented.

**Segmented** [`OSegmented`]. Picks one of two to four options with a sliding thumb. For more than four, use a menu submenu or the layout thumbnail grid.

**Slider** [`OSlider`, `OBarSlider`, `OKnob`]. Sets a number by dragging. `OSlider` has a thin track and a thumb; its value reads at the trailing edge, and nothing floats above the thumb, so it never clips. `OBarSlider` is a pill whose fill is the indicator.
- A press without movement jumps to the press point and springs there. A drag on the line follows the pointer. A drag on the bar is relative to the grab point, so it never jumps.
- Only the value rounds to `step`. The fill follows the pointer.
- Hold Option while dragging for a tenth of the speed.
- Within 2.5% of a tick, the value snaps and the thumb gives a small bump.
- Dragging past an end stretches the control a few points, then springs back.
- Double-click resets to `resetValue`. Arrow keys step. Shift gives 10 times the step.
- Pressing with the pointer does not show a focus ring. Focus from the keyboard does.
- Use the line slider inside settings rows. Use the bar for a stack of related values.

**Row and Group** [`ORow`, `OGroup`, `OSectionHeader`, `OPageTitle`]. A row has an optional symbol, a label, a description and a control on the right. A group is an open list with hairlines between rows and no box. Labels are sentence case and name the effect ("Focus follows mouse"). Put units and current values in the description, not the label.

**Template row** [`TemplateRow`]. A saved workspace shows a full-width screenshot above an `ORow` with its name, window count and display count. The screenshot preserves its aspect ratio. Click it to open a larger preview. Open is a text button. Rename, update and delete use labelled icon buttons. The Templates settings pane lists these rows without a surrounding box. Quick actions use the same saved templates, with S to save and 1–9 to open.

**Template save row** [`TemplateSaveRow`]. Cursor actions show a name field beside Save and Cancel. Return saves the template. Escape returns to the action list. The menu receives text input while the field is present. Saving does not open Settings. Hovering a saved template replaces its number with an X. Clicking the X deletes the template and keeps the menu open.

**Kbd** [`Kbd`]. Keycaps for a shortcut, a chord or a sequence. Small keycaps (20 pt, `well`) go in tooltips, labels and buttons. Menu rows use plain `kbd` text. Medium keycaps (30 pt) go in onboarding key pickers and summaries. Large keycaps (40 pt) go only in coach marks, where the real key press fills them with `accent` and sinks them 2 pt. Medium and large keycaps are flat `surfaceRaised` tiles, with no shadow and no bottom edge. Order modifiers the macOS way: control, option, shift, command, then the key.

**Tooltip** [`OTooltip`, `Tooltip`]. The smallest surface (`extraSmall`). One short phrase in sentence case, with no full stop. Never a button inside. Every icon-only button gets one. A shortcut is one chord at most. It points at its target with a small caret.

**Menu** [`Popup`, `OMenuRow`, `OMenuButton`, `OMenuPicker`]. A dropdown with groups, checks, radios, switches, inline controls and nested submenus, with type-to-search. The picker button is an outlined pill (`borderControl`) with the current value in `body-medium` and the up-down chevron.
- Menu rows carry no symbols. The lead column holds only a check, a radio dot or an app icon. A notification dot sits after the label.
- The status menu root holds five rows: search, Layout, Workspaces, Settings and Help, then the footer with the version and Quit. The search row is a `well` row at the top. The workspace strip, Bring Window Here, What's New and the tutorial live one level down, in Workspaces and Help. Search finds them all.
- Nest one level, two at most. Put the current choice of a radio group in the parent row's value.
- Every actionable row shows its shortcut.
- Give hidden aliases to commands that live inside a custom control, so search still finds them.
- Arrow keys, return and escape work. Typing focuses search.

**Welcome card and intro** [`WelcomeView`, `WordmarkView`]. The welcome card opens with the cat mascot at 72 pt, not the app icon, above the `display` title. Permission rows use `inkMuted` symbols and the page dots are `ink`. The intro wordmark is the lockup: the cat beside the wordmark, both white, with the tagline below.

**Settings window** [`SettingsView`, `Sidebar`, `SideItem`, `PaneHost`]. 880 by 620 pt by default, at least 760 by 520, at the normal window level, so it never floats above other windows. The rail is 196 pt: the animated cat mascot at 56 pt beside the 26 pt wordmark, then the search field, then the pages as text pills. The cat follows the cursor with its eyes while the cursor is over the rail. Its feeling and colour report the state: `content` in `ink` while CatWM runs, `sleepy` in `inkMuted` while tiling is paused, `annoyed` in `warning` while a shortcut has a problem, `alert` in `warning` while Accessibility or the event tap is missing, and `sad` in `danger` when the config cannot be saved. The pane shows the page title in `title`, then the groups. The status line at the top of General appears only when Accessibility or the event tap is missing. The only floating pill over the pane carries a save error, the shortcut problem count or skipped config lines.

**Overview** [`SortView`]. A flat `surface` panel with the `float` elevation, not glass. Each workspace, the Close lane and each full screen window is a `surfaceRaised` container. The add lane is a dashed slot. A hovered or selected window row is a `hover` fill, and its window in the thumbnail is `ink`. Only a drop target uses `accent` (`accentSoft` fill, `dangerSoft` on Close). The layout pill is an outlined pill, like the picker.

**Command menu**. A menu that opens with the search field first, 360 pt wide. Results group under their top-level parent and show the rest of the path as a breadcrumb. It shares its data with the menu so the two never disagree.

**Coach mark** [`.surface(.large, caret:)`]. One step of the keyboard tour: step dots, a title, a body, live keycaps and Next. A step completes only when the person presses the real key. Next appears, with the return key, after that. The kicker counts ("STEP 3 OF 6"). The done line is short ("Focus moved").

**HUD**. Confirms a keyboard action in the middle of the screen: a glass surface with a layout thumbnail and its name. Shown for about one second. Never interactive. It ignores the mouse. The warning variant wiggles `exclamationmark.triangle.fill` and names the app that refused.

**Layout picker and thumb** [`LayoutPicker`]. Picks a layout from a grid of thumbnails. The hovered layout's name and description show on one line below. Thumbnails carry no labels, so nothing wraps. Panes are `tint`. The main pane is a darker neutral. A selected main pane is `accent`. Use the app's own layout descriptions as tooltips.

**Tab strip** [`TabStripView`, `TabStrips`]. Sits on the top edge of a tab group, flat on `surface` with `large` top corners. It is inset by `pane` from each side, so it rests on the straight part of the window top and the window keeps its own traffic lights. The tabs share the width with no gap. The active tab is `ink` at 10% while the group has focus and at 6% when it does not, and the fill slides to the next tab with `Motion.easeOut`. A hovered tab is `ink` at 4%. A `hairline` separates two tabs when neither is active or hovered. Each tab fills the full strip height, so the whole tab is the hit target. Native close and minimise lights (`NativeTrafficLight`) sit at the left, inset by the same 8 pt as above and below them, with `medium` space before the first tab. They close or minimise every tab in the group, and they are grey when no tab has focus. The first tab has the same `large` top-left radius as the strip. A hovered tab shows its close button at the left. A drag of the window title bar moves the whole group: the hidden tabs and the strip follow it, and a drop on another group adds every tab. A tab dragged out of the strip carries its window under the cursor, and the drop takes it out of the group. While it is out, the other tabs fill the strip. A window dragged into a strip shows as a tab at the cursor, the strip comes above the window, and the other tabs make space. The drop adds it at that place. The strip is `rowHeight` tall. It stays on the Desktop of its group and moves with it, and Mission Control does not show it. With the "Auto-hide tab strip" setting on (off by default), every strip hides and its window fills the strip space, with or without focus. When the cursor comes above the window or into the empty title bar (`TitleBar.clearTop`, or 10 pt when the app does not tell), the strip comes back. The traffic lights, and a cursor that moves toward them, do not show it, so the person can reach them and the window moves down under it. The strip hides again 0.3 s after the cursor leaves.

**Tab group in the overview** [`SortList`, `SortTabHeader`, `SortTabBracket`]. A group is one block. A "Tab group" title row with the tab count is on top, and each tab is a row below it, indented by `tabIndent`. A `borderControl` bracket at 50% joins the tabs to the title. The bracket is 1.5 pt with round caps, and each branch bends with the `small` radius. The lane thumbnail shows the group as one tile. A drag of the title row moves the whole group, and the drag image shows the title and every tab. A drag of a tab row moves only that tab. The group stays in the overview until Done, also with one tab. A window dropped on a group joins it, and the group shows `accentSoft` while the window is above it.

**Workspace strip** [`WorkspaceStrip`]. Workspaces as pills. The current one is `accent` with `onAccent` text. Workspaces with windows are `ink` at 500. Empty ones are `inkFaint` at 400. Both meet 4.5:1.

**Cat** [`CatSymbol`, `CatFeeling`]. The CatWM cat, filled with the foreground style. A feeling sets the eyes: content, alert, sad, annoyed, sleepy or shut. A change of feeling morphs the eyes with the spring of the new feeling. `CatSymbol.image(_:height:)` gives a template `NSImage` for AppKit. The eye geometry is the same as in `docs/design/cat-feelings.html`.

**Cat mascot** [`CatMascot`, `CatMoves`]. The flat cat with life. The eyes sit on an imaginary sphere around the head, so a look turns the face: the eyes slide, get thin near the edge and go out of view behind it. The cat breathes, looks around a little and blinks at random times. `moves.play(.hop)`, `.spin`, `.wiggle` or `.look` plays a move once. The moves are keyframe tracks in `CatMotion.swift`. Use the mascot only where the cat is the subject, such as onboarding or About. Use `CatSymbol` everywhere else. With reduce motion, the mascot is a still `CatSymbol`.

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

The app icon and wordmark are in `Resources/Icon` and `Resources/Fonts`. The wordmark uses `Theme.wordmark`. `AppIcon` is the dark appearance, the white cat on black, and the bundle icon. `AppIcon-Light` is the light appearance, the black cat on white. macOS 26 can switch between the two from one Icon Composer `.icon` file compiled by `actool`. The build does not do that yet, so the dark icon shows in both appearances. `CatMark.svg` is the cat alone, filled with `currentColor`.
