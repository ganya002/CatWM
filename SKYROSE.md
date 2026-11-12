# SkyRose mods

This branch (`skyrose`) is Per's CatWM `main` plus the commits SkyRose needs to embed CatWM as its window
manager. Nothing here is pushed to noxaur/CatWM. Each mod is one commit whose title starts with
`skyrose(Mn)`, so a rebase onto a new `main` replays them one by one. SkyRose's side of the guide is
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
