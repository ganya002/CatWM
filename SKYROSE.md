# SkyRose mods

This branch (`skyrose`) is Per's CatWM `main` plus the commits SkyRose needs to embed CatWM as its window
manager. Nothing here is pushed to noxaur/CatWM; the branch lives on Gabby's fork
(https://github.com/ganya002/CatWM). Each mod is one commit whose title starts with `skyrose(Mn)`. New
upstream versions are merged in (no rebase, because the branch is published and force-push is banned). SkyRose's side of the guide is
`docs/catwm-modding.md` in the SkyRose repo.

## M1: parked workspaces (`workspaces.parked`)

SkyRose's workspaces work like Hyprland's: all of them live on the Desktop the display shows, and switching
is instant and animated by the window manager, not by the macOS Desktop swipe. Upstream CatWM makes each
workspace a native Desktop, which embedded mode can only switch with the macOS swipe.

With `workspaces.parked`, every display's current Desktop is its home. `syncParkedWorkspaces` runs the
upstream `WorkspaceReconciliation` with that home and parks what it returns in `park` with the existing
`park` and `cornerPark` (one point stays on screen, because macOS refuses to move a window fully off).
`showParkedWorkspace` swaps `virtualShown` and refreshes, and `moveParkedWindow` reuses `assignWindow`.
Parked mode turns `virtualWorkspaces` and `workspacesPerDisplay` off in `WindowManager.effective`, so
numbers are global like Hyprland's and no native Desktop code runs. A workspace first used from a display
opens on that display.

Not kept across a restart: `stop` puts every parked window back, so after a restart all windows are on
the shown workspace.

## M2: per-window commands (`window` argument)

SkyRose's app rules, CLI and panic act on a window they name, not the focused one, and they must not
steal focus to do it. Every window command whose action already honoured `ActionContext.target` is marked
with `targetingWindow()`, and its control command gains an optional `window` id. An unknown id fails with
`failed` instead of silently acting on the focused window. A targeted command skips the focus deferral,
because it does not depend on focus. `togglefloating`, `minimize` and `killactive` now read
`context.window`, so a window rule using them also acts on the rule's window. Keybind and config
argument lists are unchanged: `window` exists only on the control command.

## M3: frames hook and snapshot glide for embedded hosts

SkyRose draws borders and wants Hyprland's glide. CatWM already has Bézier curves, durations and the
snapshot resize scene, so SkyRose configures those instead of animating windows itself. Two things were
missing in embedded mode: `CatWMEngine.onWindowFrames` (each animation frame's in-flight frames, fed from
the `WindowPresentation` sampling in `Animator`) and the snapshot scene, whose install moved from the app's
`AppSurface` into `Animator.useSnapshotScenes` so `EngineSurface` can call it. The host's own windows are
excluded from the scene's occlusion check. `CatWMEngine.onStateChange` (the manager's `onChange`, run on
every refresh) lets the host follow windows changing workspace, which emits no event.

## M4: dwindle layout

Hyprland's dwindle with `togglesplit`, `swapsplit`, `splitratio` on the focused split and relative
`resizeactive DX DY` (Hyprland's argument form; it used to be rejected). See `docs/internals/dwindle.md`.
The tree lives in `ScreenState.dwindle` and maps positionally onto `order`, so CatWM's existing swap and
move commands keep working.

## M4b: `pseudo` and `pin`

`pseudo` keeps a tiled window at its own size (the size it arrived with, or had when it last stopped
floating), centered in its tile; it is applied in `rawSlots`, so every layout supports it. `pin` makes a
floating window follow the shown workspace in parked mode (`showParkedWorkspace` reassigns pinned windows
before the refresh parks the old workspace). Outside parked mode `pin` logs and does nothing, because
native Desktops can't show another app's window everywhere without private API.

## M5: special workspace (`togglespecialworkspace`, `special:<name>`)

Hyprland's scratchpad. `special` or `special:<name>` resolves to the workspace `special:<name>`, which is
an ordinary parked workspace, so moving a window there hides it. `togglespecialworkspace` brings its
windows onto the shown workspace as centered floating windows and remembers their floating state; a
second toggle sends them back and restores it. Any explicit workspace move of one of those windows takes
it out of the special set, which is how `movetoworkspace` out of special works. Parked mode only.

The `screens` state reports the open special workspace as `special` (null when none), so a host's bar can
show it.
