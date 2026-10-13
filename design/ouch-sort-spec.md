# Sort Windows

A panel that sorts a crowded display into tidy, tiled workspaces. It sorts live: your real windows move
as you edit, Revert puts everything back, Done keeps it. It can be opened at any time, and Ouch offers
it after the tour and when a workspace gets crowded.

- Interactive prototype: `design/ouch-sort-prototype.html` (open it in a browser) and
  https://claude.ai/artifact/2pbxWU4Kwp6V8onECy9Bjp. When the prototype and this spec disagree, the spec wins.
- Design system: https://claude.ai/artifact/GY1GAH7xBUwAzBP1B9mtfY, already ported to SwiftUI in
  `Theme.swift` and `Components.swift`. Use those tokens, `.surface(...)` densities and components;
  invent no new colours, fonts or weights.

## Scope

Works in Ouch-workspaces mode (`config.virtualWorkspaces`). In macOS-Spaces mode the menu item is
disabled, the `sort` dispatcher shows a HUD ("Sorting needs Ouch workspaces"), and no nudge appears.

## Ways in

1. **Menu bar menu**: a `Sort Windows…` item in `StatusMenu` (symbol `square.grid.3x1.below.line.grid.1x2`
   or similar), showing its configured shortcut and a count badge (`accent-soft`/`accent-ink`) when the
   focused workspace holds more windows than `sort-nudge`.
2. **Shortcut**: a new `sort` dispatcher. Default bind `bind = $mod, o, sort` in both default configs.
   Toggles the panel. Listed in `Actions.all` / `Actions.dispatchers` so Settings and the shortcut map know it.
3. **After the tour**: when the tour ends and the user's returned windows on the focused workspace exceed
   `sort-nudge`, the closing card offers "Sort my windows" / "Keep as is" (accent-tone `lg` surface,
   caret at the menu bar icon, kicker "STEP n OF n"). Reuse the existing tour card styling.
4. **Crowded nudge**: a tip under the menu bar icon (`md` surface, lead `lightbulb` breathing, close
   button) titled "Workspace N is packed", body "N windows share one screen. Sort them into workspaces
   by what they're for.", a thin strip with one segment per window, buttons "Sort windows ⌥O" (shows the
   real bind), "Not now", and a "No more tips" link that writes `sort-nudge = 0` into the config (through
   the Settings document, so an open Settings window doesn't write the old value back).
   Shown at most once per workspace per day, when the focused workspace's window count exceeds
   `sort-nudge` (default 8). Never while the tour runs or tiling is paused. `sort-nudge = 0` also hides
   the menu badge and the post-tour offer. The post-tour offer counts as "Keep as is" after 20 s.

## The panel

A key-capable borderless `NSPanel` (pattern: `MenuPanel` in StatusMenu.swift), on the display under the
pointer, bottom-centred, `lg` surface on glass, about 1100pt wide (clamped to the screen). No dimming of
the screen. It sorts live: every edit is applied to the real windows at once (see "Live sorting").

While it is open, pause the global key tap (`Hotkeys.shared.paused`) and handle keys in the panel, then
restore on every way out. Esc or Revert reverts; Done, ⏎, a click outside, the `sort` bind again or
double-clicking a workspace keep the changes (see "Live sorting").

### Layout, top to bottom

- **Header**: title "Sort **N** windows" (title style, N in `accent-ink` at 500). Then a display
  picker (segmented control: a small screen glyph, the display's short name, its window count) when more
  than one display exists. Then, right-aligned, a segmented control of groupings: By task, By app, Focus,
  Start empty.
- **Workspace columns**, in a horizontally scrolling row, each 176pt wide:
  - Header row: the workspace's real name, usually its number (light 22pt, `accent-ink` when it has windows), an editable name field
    (heading style, placeholder "Workspace N"), the window count, and a remove (×) button shown on hover.
  - A layout thumbnail (16:10, `sunken` ground, `tint` panes, main window slightly darker, the pane of
    the window under the pointer in `accent-2`). Use the real `Layout.frames` maths so it matches tiling.
  - A layout pill (layout icon + name): click for the next layout in `config.layouts`, right-click for the
    previous one (no context menu). Its tooltip: "Click for next layout, right-click for previous". The same
    on the new-workspace column's sticky pill.
  - Dragging the column by its number, count or thumbnail (not the name field, not the rows) carries the
    whole workspace; it follows the pointer like a row does (popover shadow, no tilt, no border). Dropped
    on Close it marks all its windows for Close and its column goes, like removing a workspace except
    the windows go to Close (with the same footer notice and Undo). Close is its only drop target.
  - The window rows: 30pt menu rows (app icon, title truncated with ellipsis, app name in `ink-faint`).
    Hover = `hover`; the pointed-at or selected row = `accent-soft`. The list scrolls vertically past
    about 7 rows; hovering or pointing at a row shows an × at its right (same look and behaviour as the
    workspace remove button) that sends the window to Close; scrolling must never scroll the row of columns, and sideways scrolling over a window
    must scroll the row of columns.
  - Empty workspace: a dashed 30pt drop slot, no text.
- **New workspace column** (after the last workspace): the same size as a workspace column but with
  "+ Workspace N" (N being the name the new workspace would get), an empty preview the same size as a thumbnail (dashed outline, no windows), and a
  layout pill. The layout chosen there is sticky: every workspace added uses it until changed. Click it,
  drop a window on it, press `+`, or send a window to the next free number to add a workspace. Max 10.
- **Close column**, pinned at the right outside the scroll, after a hairline. Shaped like a workspace
  column so its rows line up: a header with a light 22pt `xmark` in `danger`, "Close" in `ink` and the
  count; a 16:10 drop box where the thumbnail would be (dashed outline and an `xmark.circle` in
  `ink-faint` when empty, `danger-soft` with a `danger` symbol when it holds windows or one is dragged
  over it); an empty slot where the layout pill would be; then the window rows, titles struck through.
  A window put here (by any route: row ×, drag, dragging a workspace, the duplicates button, keys) is
  hidden from the screen at once and the others retile; it is closed when the panel finishes (via the
  window's close button, so apps can ask to save) and comes back if it is brought back or the panel is
  reverted. Closed workspaces appear as groups:
  a small header row (number or name, window count) with their windows indented below; other windows
  are plain rows. Clicking a closed window brings it back to the workspace it came from, at its old place
  (the whole workspace if that is closed too; the shown workspace if it was removed otherwise). Clicking a
  closed workspace's header brings it back with all its windows, under the same name and in numeric order
  if the name is still free, else the next free one. In Close an × is replaced by a restore symbol
  (`arrow.uturn.backward`, `ink-muted`) that does the same; rows get a hover ground and the tooltip
  "Click to bring back". Restores are live edits like any other, and Revert/Undo cover them.
- **Footer** (hairline above): an optional "Close N duplicate <App> windows" ghost button with an `xmark.circle`
  (shown only when two or more windows of one app have identical titles and the extras aren't in Close
  yet). Nothing is marked until it is clicked; clicking moves the extras into Close, where each can be
  clicked back, and the button goes away (picking a grouping afterwards keeps them in Close). Then a notice with Undo when there is one (no summary line), then a ghost "Revert" button showing `esc` and a
  primary "Done" button showing `⏎`. There is no Sort button and no Cancel: changes are already applied,
  so the only choices are keeping them (Done) or putting everything back (Revert).

No explanatory text anywhere else: no key hint lines, no captions.

### Groupings

- **By task**: map bundle IDs to Code, Web, Chat, Media, Files (a built-in table, e.g. Xcode, Terminal,
  Ghostty, iTerm, VS Code, Cursor → Code; Safari, Chrome, Arc, Firefox, Zen → Web; Slack, Messages, Mail,
  Discord, Teams → Chat; Music, Spotify, Preview, Photos, Figma → Media; Finder, Notes and everything else
  → Files). Empty groups are dropped.
- **By app**: the four busiest apps get their own workspace, the rest go to "Everything else".
- **Focus**: the three most recently focused windows stay in workspace 1 "Now", everything else goes to
  "Later" with the Fullscreen layout.
- **Start empty**: every window in one workspace.
- Layout per workspace picked by count: 1 → fullscreen, 2 → column, 3 → tall, 4 → bsp, 5+ → tall (only
  layouts present in `config.layouts`; fall back to the first).
- A display that is already sorted (more than one workspace with windows on it) opens on its current
  workspaces with no grouping selected; picking a grouping re-sorts.

### Workspaces: add, remove, numbering

- A column is a real workspace and shows its real name (its number), in the header, in the placeholder
  ("Workspace 3") and in "+ Workspace N". Columns stay in numeric order; a display's columns need not be
  1, 2, 3 (display B showing workspace 2 leaves A with 1, 3, 4, 5).
- A new column takes the display's own free workspace first, then the first free number. A name is free
  when no column here, no other display and no column of any other open plan uses it. Max 10 columns.
- Remove (×): its windows move to the column before it (or after it, for the first). The others keep
  their names, so only the removed name becomes free. The footer shows "Removed Chat. Its 3 windows
  moved to 2." with Undo (also ⌘Z). The last column cannot be removed.

### Moving windows

- Drag a row to another column, to the new-workspace column, to Close, or onto a display in the header.
  The dragged row follows the pointer with a popover shadow: no tilt, no outline, no border on landing.
  The target column gets an `accent-soft` ground. Dragging near the row's edges scrolls it.
- Keys act on the row under the pointer, else the selected row. They come from the user's config:
  read the binds of the `window` mode (else the first mode; with no modes, the global binds) from `config.bindings`:
  - `movefocus` dir: over a row, moves that window; otherwise moves the selection.
  - `movewindow l|r`: to the neighbouring workspace at the same position; `u|d`: reorder within the
    workspace (top = main window).
  - `movetoworkspace N` / `e±1`: send to the workspace named N (a column is made for it when N is free); `e±1` steps to the neighbouring column.
  - `cyclelayout next|prev`: the window's workspace layout.
  - `layoutmsg swapwithmaster`: move to the top.
  - `focusmonitor ±1`: switch the display being sorted.
  - `movewindow mon:±1`: move the window to that display's **active workspace** (the workspace it is
    showing). The footer says "Moved <title> to <display>, <workspace name or number>."
  - `killactive`, ⌫, ⌦, x: toggle Close (a window already in Close comes back, as when clicked).
  - Always: plain 1–0 (by key code, so any keyboard layout) send to the workspace with that name, `+` (the key that types it, or the keypad one; `=` on a US layout) adds a workspace, ⏎ keeps the changes and closes, Esc reverts, ⌘Z undoes the
    last remove (and re-applies live).
- Each display keeps its own pending edits while the panel is open; switching display does not lose them.

### Live sorting

- Opening the panel takes one snapshot of the original state for every display: assignment, order,
  `monitorOf`, labels, each workspace's layout, ratio and main count, and the workspaces shown. Live
  applies never overwrite it. On a display that isn't sorted yet, the grouping from `sort-strategy`
  counts as an edit and is applied as the panel opens, so the panel and the screen always agree; Esc
  puts it back. A display that is already sorted opens as it is and moves nothing until you edit.
- Every edit is applied to the real windows right away, debounced (about 150 ms, trailing) so held keys
  and bursts retile once, and only for the plans that changed: moving or reordering windows, layout
  changes, adding, removing and renaming workspaces, moves between displays, and switching the
  grouping. It sets each window's workspace (`workspaceOf`) and place in `order`, each workspace's
  layout and label, and `monitorOf` for new workspaces, then `refresh()`. Windows animate to their tiles
  with the normal animator.
- A live apply never focuses or activates a window or app, never switches workspace, and never takes the
  keyboard from the panel. Every display keeps showing the workspace it showed; only if that workspace
  was removed is the first one with windows shown, without focus. Focus following the mouse and the
  follow-focus switch are paused while the panel is open. If something still pulls the key away during
  an apply, the panel takes it back instead of closing.
- Windows in Close are hidden live: they are parked off-screen like windows of a hidden workspace, on a
  per-display pseudo workspace (`sort-close:<display>`) that is never shown. It never leaks: it is left out
  of the workspace list, the menu bar strip, the HUD, workspace switching and the Sort panel, and it is
  never saved. Bringing a window back from Close unhides it into its restored workspace, live. Hiding does
  not move focus or take the keyboard from the panel. Quitting or being killed mid-sort puts parked
  windows back on screen without closing anything; a crash leaves them to be picked up again on the next
  launch, as with any parked window. Windows that close while it is open vanish
  from it; windows that open meanwhile are left alone, and land on a workspace that remains. If tiling is
  paused the assignments still change and the windows settle when tiling resumes.
- **Revert** (Esc, or the footer button) restores the snapshot, closes nothing (hidden windows come back exactly
  where they were) and closes the panel. Focus and the shown workspaces stay as they were.
- **Finish** keeps the changes: Done or ⏎, a click outside the panel, the `sort` bind again, a change of displays
  (changes kept), or double-clicking a workspace's thumbnail or number, which also shows that workspace
  and focuses its main window. Windows in Close are closed where they are, still hidden, so they just disappear. About
  0.8 s later Ouch checks: a window still open (most likely an app asking to save) is brought onto the
  workspace its display shows so its sheet can be answered, and the close is retried (the app's Close
  Window menu item for a focused window with no close button). Anything else left hidden goes back to
  the shown workspace. A window still being closed stays hidden through a new panel, its Revert and the
  toast's Undo. Workspaces a sort lets go of lose their names. What happens to each window is
  written to `~/Library/Logs/ouch.log`. Only Done/⏎
  and the double-click focus a window (Done returns to the window that had focus when the panel opened).
  Then a toast (`sm` surface): "Sorted into 5 workspaces, closed 2" with an Undo button (about 6 s; the
  `sort-undo` action is bindable, with no default bind) that restores the snapshot (closed windows stay
  closed). If nothing was changed, finishing is silent and shows no toast.
- If the workspace mode changes under the open panel (config reload), the panel closes and lets go.
- Workspace names are stored as labels (persist with the workspace assignments) and shown in the HUD on
  switch ("2 · Web").

## Config

```
sort-nudge = 8          # windows on one workspace before Ouch offers to sort; 0 turns the nudge off
sort-strategy = task    # task | app | focus | none: the grouping the panel opens with
bind = $mod, o, sort
```

Both options must be parsed in `Config.apply`, written back by `ConfigDocument`, and editable in Settings.

## Out of scope for now

macOS-Spaces mode, moving windows between displays by dragging on the desktop, custom app groups
(`sort-group`).
