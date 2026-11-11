# Vocabulary

Use these words in code, docs, UI text and commit messages. Each word has one meaning.

- **cursor** means the macOS cursor.
- **workspace** means an CatWM workspace, not a macOS Desktop.
- **Desktop** means a macOS Space. Each normal Desktop is one CatWM workspace.
- **fullscreen** means CatWM fullscreen: one window fills the screen, and CatWM still manages it.
- **maximised** means macOS native full screen: the window gets a Desktop of its own and leaves the tiling.
- **bind** means a key combination that runs a dispatcher. It is a `bind = …` line in the config.
- **dispatcher** means a named command, such as `movefocus` or `workspace`. `WindowManager.dispatch` runs it.
- **submap** means a set of binds that is active at one time. The event tap matches each key press against the active submap.
- **window mode** means a mode where single keys control windows. A global shortcut enters it, and keys with no bind are ignored. In the config it is the `window` submap. A right click on a window opens its context menu.
- **overview** means the Sort menu. Sort is the old name, and the code folder and types still use it.
- **switcher** means the window switcher. `$mod Tab` opens it, and the `switcher` dispatcher runs it.
- **template** means a saved workspace template: the windows, workspaces, Desktops, layouts and frames of a setup. `Templates/` owns it.
- **session** (in `Session/`) means the save and open of app windows. It has no CatWM types. See `window-session.md`.
- **agent display** means a private virtual display that an agent's apps open their windows on. The user's CatWM ignores it. See `agent-display.md`.
