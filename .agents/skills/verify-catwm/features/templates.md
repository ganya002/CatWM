# Template restore

The user opens a saved workspace template. CatWM finds its windows, restores the display layout and frames, and restores minimized windows. A restored minimized window must return to tiling when the user opens it again.

## Sub-features

- Restore through Settings > Templates > Open.
- Restore the saved layout and floating frame.
- Restore minimized state, then release its placement hold when the window opens again.

## How to get to it (user POV)

- Open CatWM Settings, select Templates, and click Open on a saved template.
- In TextEdit, select a minimized test window from the Window menu to open it again.

## Driving it with the catwm CLI

Use an unscoped named instance with approval, the host lock, and three scratch TextEdit windows. A scoped instance refuses template restore. Keep the user's CatWM from writing test frames during the run, then restore its previous state during cleanup.

Prepare a template in the test instance's own library before that instance first opens Templates. Use the `TemplateLibrary.Stored` JSON format, version 1. Use only `DESK_PID` windows. Read the window IDs, titles, document URLs and display UUID from the scratch setup. Save these choices:

- Tiling enabled, `wide` layout, ratio 0.65, one main window.
- First window floating at `(120, 120, 500, 400)` and focused.
- Second window tiled.
- Third window minimized.

Keep the template fixture with the evidence. Do not replace the user's template library. Disable `template-app-scripting` in the test instance to keep this check independent of Automation permissions.

1. Save `template-before` evidence. Open Settings > Templates and click Open on the fixture.
2. Wait for Settings to report `Opened <name>.` rather than `Opening…` or a partial result.
3. Poll `screens --json` and `windows --json`. Check the `wide` layout, the first window's floating state and saved frame within 8 points, and the third window's minimized state.
4. Check `dump`: every tiled test window must have matching target and actual frames. Save `template-after` evidence.
5. Save `held-window-before` evidence. In TextEdit's Window menu, select the third window.
6. Poll until it is visible and no longer minimized. Check that its own `tiled <id>` row in `dump` reports `OK`. Save `held-window-after` evidence.
7. Run cleanup. Check that the test process stopped, the original Desktop returned, and the user's CatWM has its original tiling state.

## Gotchas

- Reopening CatWM opens Settings. With several copies running, a UI tool can select the wrong copy. Check the executable and instance before interacting.
- Template files load when the library initializes. Writing a fixture after Templates opens does not reload it.
- Template capture, app launching, the cursor-menu entry point and restore cancellation need separate live evidence. This recipe covers restoration of existing windows through Settings.
