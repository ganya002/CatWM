// Every feature on the features page. Keys, commands and settings come from
// Sources/CatWM/Config/Model/defaultBinds.swift, WindowActions.all and Options.swift.
// Change them together.

import { type Scene, tiled } from "~/catwm/cards";
import type { Hue } from "~/catwm/script";

export type Media =
  | { kind: "demo"; caption: string; hold: number; scenes: Scene[] }
  | { kind: "image"; caption: string; src: string; alt: string }
  | { kind: "code"; caption: string; code: string };

// A Settings pane as the app shows it: each row with its default control.
// true or false is a switch, a string is a menu value, button is a button.
export type Control = boolean | string | { button: string };
export type Settings = { pane: string; rows: [string, Control?][] };

export type Feature = {
  id: string;
  name: string;
  line: string;
  body: string;
  keys?: string[][];
  settings?: Settings;
  cli?: string[];
  config?: string[];
  media?: Media;
};

export type Category = { id: string; name: string; hue: Hue; features: Feature[] };

const ABC = ["a", "b", "c"];
const ABCD = ["a", "b", "c", "d"];

const demo = (caption: string, hold: number, scenes: Scene[]): Media => ({
  kind: "demo",
  caption,
  hold,
  scenes,
});
const image = (caption: string, src: string, alt: string): Media => ({
  kind: "image",
  caption,
  src,
  alt,
});
const code = (caption: string, text: string): Media => ({ kind: "code", caption, code: text });

export const USER: Category[] = [
  {
    id: "window-mode",
    name: "Window mode",
    hue: "sky",
    features: [
      {
        id: "enter-window-mode",
        settings: { pane: "Shortcuts", rows: [["Window mode", "⌘⇪"]] },
        name: "Window mode",
        line: "One chord, then single keys move your windows.",
        body: "Press ⌘ Caps Lock, then use single keys to move your windows. Esc leaves. ⌘ and ⌃ shortcuts still reach your apps.",
        keys: [["⌘", "⇪"], ["Esc"]],
        cli: ["catwm submap window", "catwm submap reset"],
        config: ["bind = SUPER, capslock, submap, window"],
        media: demo("⌘ Caps Lock, then L, J, H", 1500, [
          { key: "⌘⇪", shift: 0, tiles: tiled(ABC, "tall", "a") },
          { key: "l", shift: 0, tiles: tiled(ABC, "tall", "b") },
          { key: "j", shift: 0, tiles: tiled(ABC, "tall", "c") },
          { key: "h", shift: 0, tiles: tiled(ABC, "tall", "a") },
        ]),
      },
      {
        id: "keyboard-help",
        settings: { pane: "Shortcuts", rows: [["Show keyboard help", true]] },
        name: "Keyboard help",
        line: "See every key of window mode on a keyboard.",
        body: "Press ? in window mode to see each key on a keyboard. Hold Shift for the second layer.",
        keys: [["?"]],
        config: ["keyboard-help = true", "keyboard-help-key = ?"],
        media: image(
          "Keyboard help",
          "/media/window-mode-keys.png",
          "The keyboard help overlay, with the window mode keys",
        ),
      },
      {
        id: "mode-effect",
        settings: { pane: "Motion", rows: [["Window mode effect", "Draw"]] },
        name: "Mode effect",
        line: "The screen edges show that window mode is on.",
        body: "A thin effect runs along the screen edges while window mode is on.",
        config: ["mode-effect = draw"],
      },
      {
        id: "window-menu",
        name: "Window menu",
        line: "Right-click a window to float it, move it or retile.",
        body: "Right-click a window in window mode to float it, move it, or take it out of its tabs.",
        keys: [["Right click"]],
      },
      {
        id: "instant-caps-lock",
        settings: {
          pane: "General",
          rows: [["Instant Caps Lock shortcuts", { button: "Allow…" }]],
        },
        name: "Instant Caps Lock",
        line: "Removes the macOS Caps Lock delay.",
        body: "Removes the macOS delay on Caps Lock, so window mode starts at once.",
      },
    ],
  },
  {
    id: "focus-and-move",
    name: "Focus and move",
    hue: "lemon",
    features: [
      {
        id: "move-focus",
        name: "Focus a neighbour",
        line: "Go to the window on the left, below, above or right.",
        body: "H J K L or the arrow keys. In the WASD set, W A S D. From any app, hold ⌃ ⌥ with H J K L.",
        keys: [["H"], ["J"], ["K"], ["L"], ["⌃", "⌥", "H"]],
        cli: ["catwm movefocus left"],
        media: demo("H J K L", 1300, [
          { key: "l", shift: 0, tiles: tiled(ABCD, "tall", "b") },
          { key: "j", shift: 0, tiles: tiled(ABCD, "tall", "c") },
          { key: "j", shift: 0, tiles: tiled(ABCD, "tall", "d") },
          { key: "h", shift: 0, tiles: tiled(ABCD, "tall", "a") },
        ]),
      },
      {
        id: "cycle-focus",
        name: "Next and previous window",
        line: "Step through the windows in order.",
        body: "Tab goes forward, Shift Tab goes back.",
        keys: [["Tab"], ["⇧", "Tab"]],
        cli: ["catwm cyclenext", "catwm cyclenext prev"],
      },
      {
        id: "move-window",
        name: "Move a window",
        line: "Push the focused window in a direction.",
        body: "Hold Shift with a direction. The window moves past its neighbours. From any app, hold ⌃ ⌥ ⇧.",
        keys: [
          ["⇧", "H"],
          ["⇧", "J"],
          ["⇧", "K"],
          ["⇧", "L"],
          ["⌃", "⌥", "⇧", "H"],
        ],
        cli: ["catwm movewindow r"],
        media: demo("Shift L, then Shift H", 1500, [
          { key: "⇧l", shift: 0, tiles: tiled(["b", "a", "c"], "tall", "a") },
          { key: "⇧h", shift: 0, tiles: tiled(ABC, "tall", "a") },
        ]),
      },
      {
        id: "swap",
        settings: { pane: "Shortcuts", rows: [["Keyboard shortcuts", { button: "Add Shortcut" }]] },
        name: "Swap windows",
        line: "Swap with a neighbour, or with the next window.",
        body: "No default key. Add one in Settings.",
        cli: ["catwm swapwindow left", "catwm swapnext"],
      },
      {
        id: "close-minimise",
        name: "Close and minimise",
        line: "Close or minimise the focused window.",
        body: "X closes the window. Minus minimises it.",
        keys: [["X"], ["-"]],
        cli: ["catwm killactive", "catwm minimize"],
      },
      {
        id: "follow-mouse",
        settings: {
          pane: "Windows",
          rows: [
            ["Focus follows mouse", true],
            ["Only in window mode", true],
            ["Mouse follows focus", true],
          ],
        },
        name: "Focus follows the pointer",
        line: "Point at a window to focus it.",
        body: "Point at a window to focus it. By default, only in window mode.",
        config: [
          "focus-follows-mouse = true",
          "focus-follows-mouse-in-mode-only = true",
          "mouse-follows-focus = true",
        ],
      },
      {
        id: "drag-to-swap",
        settings: { pane: "Windows", rows: [["Drag to swap", true]] },
        name: "Drag to swap",
        line: "Drop a tiled window on another to swap them.",
        body: "Drag a tiled window onto another to swap them.",
        keys: [["Drag"]],
        config: ["mouse-swaps-windows = true"],
      },
    ],
  },
  {
    id: "layouts",
    name: "Layouts",
    hue: "magenta",
    features: [
      {
        id: "cycle-layouts",
        settings: { pane: "Layout", rows: [["Active layouts", "BSP, Wide, Floating, Fullscreen"]] },
        name: "Layouts",
        line: "Sixteen layouts. Each workspace has its own.",
        body: "N and P go through your layouts. S and Shift S do the same. Each workspace keeps its own.",
        keys: [["N"], ["P"], ["S"], ["⇧", "S"]],
        cli: ["catwm layout bsp", "catwm cyclelayout next"],
        config: ["layouts = bsp, wide, floating, fullscreen"],
        media: demo("N goes through Tall, Wide, BSP and Column", 1700, [
          { key: "n", shift: 0, tiles: tiled(ABCD, "tall", "a") },
          { key: "n", shift: 0, tiles: tiled(ABCD, "wide", "a") },
          { key: "n", shift: 0, tiles: tiled(ABCD, "bsp", "a") },
          { key: "n", shift: 0, tiles: tiled(ABCD, "column", "a") },
        ]),
      },
      {
        id: "resize-main",
        settings: { pane: "Layout", rows: [["Main pane resize step", "5%"]] },
        name: "Resize the main pane",
        line: "Make the main window larger or smaller.",
        body: "Full stop makes the main pane larger. Comma makes it smaller.",
        keys: [["."], [","]],
        cli: ["catwm splitratio +0.05", "catwm splitratio exact 0.6"],
        config: ["window-resize-step = 5%"],
      },
      {
        id: "main-count",
        name: "More main windows",
        line: "Put two or more windows in the main pane.",
        body: "Shift comma adds a window to the main pane. Shift full stop removes one.",
        keys: [
          ["⇧", ","],
          ["⇧", "."],
        ],
        cli: ["catwm layoutmsg addmaster", "catwm layoutmsg removemaster"],
      },
      {
        id: "swap-main",
        name: "Swap with main",
        line: "Put the focused window in the main pane.",
        body: "M puts the focused window in the main pane. Shift M swaps the two sides. G focuses the main window.",
        keys: [["M"], ["⇧", "M"], ["G"]],
        cli: ["catwm layoutmsg swapwithmaster", "catwm layoutmsg swapsides"],
        media: demo("M", 1500, [
          { key: "l", shift: 0, tiles: tiled(ABC, "tall", "b") },
          { key: "m", shift: 0, tiles: tiled(["b", "a", "c"], "tall", "b") },
        ]),
      },
      {
        id: "split-handle",
        settings: {
          pane: "Windows",
          rows: [
            ["Split handle", true],
            ["Drag window edges to resize the main pane", true],
          ],
        },
        name: "Split handle",
        line: "Drag the bar between panes. Click it to swap sides.",
        body: "Drag the bar between the panes to resize them. Click it to swap the sides.",
        keys: [["Drag"]],
        config: ["split-handle = true", "mouse-resizes-windows = true"],
      },
      {
        id: "gaps",
        settings: {
          pane: "Layout",
          rows: [
            ["Gaps between windows", true],
            ["Gap size", "10 pt"],
            ["Smart gaps", true],
            ["Screen padding", "10 pt"],
            ["No padding on the built-in display", true],
          ],
        },
        name: "Gaps and padding",
        line: "Space between windows and at the screen edges.",
        body: "With one window on the screen, CatWM removes the gaps.",
        config: [
          "window-margin-size = 10",
          "smart-window-margins = true",
          "screen-padding = 10",
          "disable-padding-on-builtin-display = true",
        ],
      },
      {
        id: "layout-hud",
        settings: {
          pane: "Layout",
          rows: [
            ["Show layout name on change", false],
            ["Also when switching spaces", true],
          ],
        },
        name: "Layout name",
        line: "Shows the name of the layout when it changes.",
        body: "A small card shows the name of the layout when it changes.",
        config: ["enables-layout-hud = false", "enables-layout-hud-on-space-change = true"],
      },
      {
        id: "new-to-main",
        settings: { pane: "Windows", rows: [["New windows become main", false]] },
        name: "New windows go to main",
        line: "Open new windows in the main pane.",
        body: "Open new windows in the main pane, not in the stack.",
        config: ["new-windows-to-main = false"],
      },
      {
        id: "retile",
        settings: { pane: "General", rows: [["Tiling", true]] },
        name: "Retile and pause tiling",
        line: "Put each window back in its slot, or stop tiling.",
        body: "Z puts each window back in its slot. Shift T pauses tiling.",
        keys: [["Z"], ["⇧", "T"]],
        cli: ["catwm retile", "catwm toggletiling"],
      },
    ],
  },
  {
    id: "workspaces",
    name: "Workspaces",
    hue: "lime",
    features: [
      {
        id: "native-desktops",
        settings: { pane: "Windows", rows: [["Control macOS Desktops with CatWM", true]] },
        name: "Real macOS Desktops",
        line: "Each workspace is one macOS Desktop.",
        body: "Each workspace is a real macOS Desktop. CatWM adds and removes them for you.",
        config: ["virtual-workspaces = true"],
        media: image(
          "Workspaces",
          "/media/workspaces.webp",
          "CatWM switches between macOS Desktops",
        ),
      },
      {
        id: "go-to-workspace",
        name: "Go to a workspace",
        line: "Ctrl and a number, from anywhere.",
        body: "Ctrl and a number, from any app. In window mode, the number alone. ` goes back to the last workspace.",
        keys: [
          ["⌃", "1"],
          ["⌃", "←"],
          ["⌃", "→"],
          ["`"],
        ],
        cli: ["catwm workspace 2", "catwm workspace previous"],
        media: demo("1, then 2", 2000, [
          {
            key: "1",
            shift: 0,
            tiles: [...tiled(ABC, "tall", "a"), ...tiled(["d", "e"], "column", "d", 1)],
          },
          {
            key: "2",
            shift: 1,
            tiles: [...tiled(ABC, "tall", "a"), ...tiled(["d", "e"], "column", "d", 1)],
          },
        ]),
      },
      {
        id: "move-to-workspace",
        name: "Move a window to a workspace",
        line: "Send the window and go with it, or stay.",
        body: "Ctrl Shift and a number moves the window, and you go with it.",
        keys: [
          ["⌃", "⇧", "1"],
          ["⇧", "1"],
        ],
        cli: ["catwm movetoworkspace 3", "catwm movetoworkspacesilent 3"],
      },
      {
        id: "empty-workspaces",
        settings: {
          pane: "Windows",
          rows: [
            ["Remove empty workspaces when you leave them", true],
            ["Stay on this workspace when closing a window", true],
          ],
        },
        name: "Remove empty workspaces",
        line: "An empty workspace goes away when you leave it.",
        body: "A workspace with no windows goes away when you leave it.",
        config: ["remove-empty-workspaces = true", "stay-on-workspace-after-close = true"],
      },
      {
        id: "swipes",
        settings: { pane: "Shortcuts", rows: [["Keyboard shortcuts", { button: "Add Shortcut" }]] },
        name: "Swipes and scroll",
        line: "Trackpad swipes follow your fingers.",
        body: "Swipes between Desktops follow your fingers. You can bind gestures to any action.",
        config: ["bind = $mod, swipe_left, workspace, r+1"],
      },
      {
        id: "bring-here",
        name: "Bring a window here",
        line: "Pull a window from another Desktop.",
        body: "Pick a window in the menu bar, and it moves to this Desktop.",
      },
    ],
  },
  {
    id: "displays",
    name: "Displays",
    hue: "sky",
    features: [
      {
        id: "focus-display",
        name: "Focus a display",
        line: "Go to the next or previous display.",
        body: "W goes to the next display, B to the previous one.",
        keys: [["W"], ["B"]],
        cli: ["catwm focusmonitor +1"],
      },
      {
        id: "move-to-display",
        name: "Move a window to a display",
        line: "Send the focused window to another display.",
        body: "Shift W and Shift B move the window to another display.",
        keys: [
          ["⇧", "W"],
          ["⇧", "B"],
        ],
        cli: ["catwm movewindow mon:+1"],
      },
      {
        id: "per-display",
        settings: { pane: "Windows", rows: [["Number workspaces on each display", true]] },
        name: "Workspaces on each display",
        line: "Each display counts its workspaces from 1.",
        body: "Each display counts its workspaces from 1, and keeps them when you unplug it.",
        cli: ["catwm screens"],
        config: ["workspaces-per-display = true"],
      },
    ],
  },
  {
    id: "floating",
    name: "Floating and fullscreen",
    hue: "lemon",
    features: [
      {
        id: "toggle-floating",
        settings: { pane: "Windows", rows: [["Float small windows", true]] },
        name: "Float a window",
        line: "Take a window out of the tiles, or put it back.",
        body: "V takes the window out of the tiles, or puts it back. From any app, ⌃ ⌥ V. Dialogs float on their own.",
        keys: [["V"], ["⌃", "⌥", "V"]],
        cli: ["catwm togglefloating"],
        config: ["float-small-windows = true"],
      },
      {
        id: "floating-apps",
        settings: { pane: "Windows", rows: [["Apps in the list", "Float"]] },
        name: "Apps that always float",
        line: "List the apps that never tile.",
        body: "Apps in the list always float. Or tile only the apps in the list.",
        config: ["floating = com.apple.calculator", "floating-is-blacklist = true"],
      },
      {
        id: "fullscreen",
        name: "Fullscreen",
        line: "Fill the screen and stay in the tiles.",
        body: "F or ⌃ ⌥ F fills the screen and keeps the window tiled. Shift F uses macOS full screen.",
        keys: [["F"], ["⇧", "F"], ["⌃", "⌥", "F"]],
        cli: ["catwm fullscreen", "catwm nativefullscreen"],
        media: demo("F", 1500, [
          { key: "f", shift: 0, tiles: tiled(["a"], "fullscreen", "a") },
          { key: "f", shift: 0, tiles: tiled(ABC, "tall", "a") },
        ]),
      },
    ],
  },
  {
    id: "tabs",
    name: "Tabs",
    hue: "magenta",
    features: [
      {
        id: "tab-groups",
        name: "Tab groups",
        line: "Put windows in tabs that share one tile.",
        body: "Ctrl and a direction puts the window in its neighbour's tabs. T takes it out.",
        keys: [["⌃", "H"], ["⌃", "L"], ["T"]],
        cli: ["catwm moveintogroup l", "catwm moveoutofgroup"],
      },
      {
        id: "switch-tabs",
        name: "Switch and order tabs",
        line: "Show the next tab, or move a tab along the strip.",
        body: "[ and ] show the next tab. Hold Shift to move the tab.",
        keys: [["["], ["]"], ["⇧", "["], ["⇧", "]"]],
        cli: ["catwm changegroupactive f", "catwm movegroupwindow b"],
      },
      {
        id: "tab-strip",
        settings: {
          pane: "Windows",
          rows: [
            ["Tab strip style", "Inset"],
            ["Auto-hide tab strip", false],
          ],
        },
        name: "Tab strip",
        line: "Click, close and right-click tabs.",
        body: "Click to show a tab, × to close it, right-click for more.",
        config: ["tab-strip-style = inset", "auto-hide-tab-strip = false"],
      },
      {
        id: "tab-badges",
        settings: { pane: "Windows", rows: [["Show notification badges on tabs", true]] },
        name: "Unread badges",
        line: "Each tab shows its unread count.",
        body: "Each tab shows its unread count from the app.",
        config: ["tab-notification-badges = true"],
        cli: ["catwm events window.notifications"],
      },
    ],
  },
  {
    id: "overview-and-switcher",
    name: "Overview and switcher",
    hue: "lime",
    features: [
      {
        id: "overview",
        settings: {
          pane: "Windows",
          rows: [
            ["Suggest Overview for a crowded workspace", true],
            ["Crowded from", "5 windows"],
          ],
        },
        name: "Overview",
        line: "Drag windows between workspaces on one screen.",
        body: "Each workspace is a column. Drag windows between them, then press Return. ⌥ O opens it, or O in window mode.",
        keys: [["⌥", "O"], ["O"]],
        cli: ["catwm sort", "catwm sort-undo"],
        config: ["sort-nudge = 5"],
        media: image(
          "Overview",
          "/media/overview.webp",
          "Windows move between workspaces in the overview",
        ),
      },
      {
        id: "switcher",
        settings: {
          pane: "Windows",
          rows: [
            ["Instant jump", true],
            ["Jump delay", "300 ms"],
          ],
        },
        name: "Window switcher",
        line: "Every window on every workspace. Type to find one.",
        body: "Tap ⌥ Tab for the last window. Hold ⌥ and type to find any window. In window mode, press /.",
        keys: [
          ["⌥", "Tab"],
          ["⌥", "⇧", "Tab"],
          ["/"],
        ],
        cli: ["catwm switcher"],
        config: ["switcher-instant-jump = true", "switcher-jump-delay = 300", "switcher-exclude ="],
      },
      {
        id: "quick-actions",
        settings: { pane: "Windows", rows: [["Quick actions at the pointer", true]] },
        name: "Quick actions",
        line: "A menu at the pointer for templates, dim and blur.",
        body: "In window mode, tap ⌘ for a menu at the pointer: save a workspace, dim or blur.",
        keys: [["⌘"]],
        config: ["cursor-actions = true"],
      },
    ],
  },
  {
    id: "templates",
    name: "Saved workspaces",
    hue: "sky",
    features: [
      {
        id: "save-workspace",
        settings: { pane: "Templates", rows: [["Saved workspace templates"]] },
        name: "Save and open workspaces",
        line: "Save your windows and layouts. Open them again later.",
        body: "Save your windows and layouts, then open them again with one key.",
        keys: [["⌘"], ["S"]],
        media: image(
          "Templates",
          "/media/templates.webp",
          "A workspace template is saved and opened again",
        ),
      },
      {
        id: "app-state",
        settings: { pane: "Templates", rows: [["Save tabs and folders", false]] },
        name: "Tabs and folders",
        line: "Also saves browser tabs, terminal folders and projects.",
        body: "Also saves browser tabs, terminal and Finder folders, and editor projects.",
        config: ["template-app-scripting = false"],
      },
    ],
  },
  {
    id: "look",
    name: "Look and motion",
    hue: "lemon",
    features: [
      {
        id: "animation",
        settings: {
          pane: "Motion",
          rows: [
            ["Animate windows", true],
            ["Animation style", "Snappy"],
            ["Duration", "0.12 s"],
            ["Curve", "Ease out"],
          ],
        },
        name: "Animation",
        line: "Windows glide to their new place at 120 Hz.",
        body: "Windows glide to their new place, and Desktops slide.",
        config: [
          "animate = true",
          "animation-duration = 0.12",
          "animation-curve = ease-out",
          "animation-bounce = 0.5",
        ],
      },
      {
        id: "dim",
        name: "Dim and blur other windows",
        line: "Make the focused window stand out.",
        body: "Dim or blur the windows that do not have focus. In window mode, D dims and Shift D blurs.",
        keys: [["D"], ["⇧", "D"]],
        cli: ["catwm toggledim", "catwm toggleblur"],
        config: ["dim-other-windows = false", "dim-strength = 0.5", "blur-radius = 20"],
      },
      {
        id: "panel-animation",
        settings: { pane: "Motion", rows: [["Panel animation", "Rise"]] },
        name: "Panel animation",
        line: "How the overview and keyboard help open.",
        body: "Choose rise, pop, focus, tile or draw.",
        config: ["panel-animation = rise"],
      },
    ],
  },
  {
    id: "keys",
    name: "Keys and settings",
    hue: "magenta",
    features: [
      {
        id: "shortcut-map",
        settings: {
          pane: "Shortcuts",
          rows: [
            ["Shortcut map", { button: "Open" }],
            ["Keyboard finish", "Auto"],
          ],
        },
        name: "Shortcut Map",
        line: "Change your keys on a picture of your keyboard.",
        body: "Click a key on a picture of your keyboard to change it.",
        config: ["keyboard-finish = auto"],
      },
      {
        id: "key-sets",
        name: "Vim or WASD",
        line: "Two key sets: the home row, or the left hand.",
        body: "Vim uses H J K L. WASD keeps your right hand on the mouse.",
        keys: [["H"], ["J"], ["K"], ["L"]],
      },
      {
        id: "shortcut-key",
        name: "Shortcut key",
        line: "Choose the modifier for the global keys.",
        body: "The modifier for the global keys. ⌥ keeps your app shortcuts free.",
        settings: { pane: "General", rows: [["Shortcut key", "⌥ Option"]] },
        config: ["$mod = ALT"],
      },
      {
        id: "saved-configs",
        name: "Saved configs",
        line: "Save, share and switch whole setups.",
        body: "Save, share and switch between whole setups.",
      },
      {
        id: "onboarding",
        name: "Tutorial and tour",
        line: "Learn the keys with practice windows.",
        body: "A short tutorial with practice windows. Open it again from the Help menu.",
      },
    ],
  },
  {
    id: "app",
    name: "The app",
    hue: "sky",
    features: [
      {
        id: "menu-bar",
        name: "Menu bar",
        line: "The workspace number, the layout and the apps.",
        body: "Shows the workspace number, the layout and the apps.",
      },
      {
        id: "updates",
        settings: {
          pane: "General",
          rows: [["Check for updates automatically", true], ["Include beta releases"]],
        },
        name: "Updates",
        line: "Updates by itself. Beta releases if you want them.",
        body: "CatWM looks for updates by itself.",
        media: code("Install", "curl -fsSL https://catwm.perwko.com/install.sh | sh -s -- --beta"),
      },
      {
        id: "login",
        name: "Open at login",
        line: "Start CatWM when you log in.",
        body: "CatWM starts in the menu bar each time you log in.",
        settings: { pane: "General", rows: [["Open at login"]] },
      },
      {
        id: "recovery",
        name: "Recovery",
        line: "Your Desktops come back if CatWM stops.",
        body: "If CatWM stops during a switch, your Desktops come back.",
      },
      {
        id: "feedback",
        name: "Send feedback",
        line: "Send a note and the log from Settings.",
        body: "Click the ladybug in Settings to send a note with the log.",
        config: ["perf-reports = false"],
      },
    ],
  },
];

// The part for agents and scripts: the same app, as commands, files and events.
// Commands and summaries come from Sources/CatWM/Control/ and Clients/README.md.
const GUIDE: Category = {
  id: "agent-guide",
  name: "Start here",
  hue: "sky",
  features: [
    {
      id: "agent-docs",
      name: "Agent docs",
      line: "Plain-text docs that ship inside the app.",
      body: "The app has a guide for agents in CatWM.app/Contents/Resources/AgentDocs/. catwm docs prints the path of that folder. Read README.md first. It tells you which file to read for the CLI, the config, the binds, the commands, the workspaces and the problems.",
      cli: ["catwm docs", "catwm help"],
      media: code(
        "AgentDocs",
        `README.md           read this first
cli.md              control CatWM from a shell
python.md           commands, waits and events from Python
config.md           every option and value format
keybinds.md         bind lines, keys, ranges, window mode
dispatchers.md      what each command does
workspaces.md       workspaces, displays and Desktops
troubleshooting.md  permissions, logs and failures`,
      ),
    },
    {
      id: "agent-facts",
      name: "Facts to know first",
      line: "Permissions, the modifier and who writes the config.",
      body: "CatWM needs the Accessibility permission. Without it, CatWM tiles nothing and no key works. The default $mod is Option (ALT), not Command. The Settings window writes catwm.conf again, so comments and the order of lines can change after a user edits a setting. Do not edit configs.json by hand.",
    },
  ],
};

const CLI: Category = {
  id: "agent-cli",
  name: "Command line",
  hue: "lime",
  features: [
    {
      id: "cli",
      name: "The catwm command",
      line: "Every bind is a command. The CLI runs the same ones.",
      body: "The app binary is also the CLI. CatWM links it as catwm in /usr/local/bin, or in ~/.local/bin. It talks to the running app through ~/.config/catwm/catwm.sock. Set CATWM_SOCKET to use another socket, or CATWM_INSTANCE to talk to a named instance. Add --json to get JSON.",
      cli: ["catwm ping", "catwm commands", "catwm workspace 2", "catwm dispatch layout bsp"],
      media: demo("catwm", 2400, [
        { typed: "catwm layout wide", shift: 0, tiles: tiled(ABCD, "wide", "a") },
        { typed: "catwm fullscreen", shift: 0, tiles: tiled(["a"], "fullscreen", "a") },
        { typed: "catwm layout tall", shift: 0, tiles: tiled(ABCD, "tall", "a") },
      ]),
    },
    {
      id: "cli-state",
      name: "Read the state",
      line: "Windows, workspaces, displays and a full report.",
      body: "status reads the state of CatWM and the permissions. windows lists each window with its ID. workspaces lists each workspace with its window IDs and displays. screens lists each display with its layout. dump prints a text report of the tiling state.",
      cli: [
        "catwm status --json",
        "catwm windows --json",
        "catwm workspaces",
        "catwm screens",
        "catwm dump",
      ],
    },
    {
      id: "cli-config",
      name: "Read and change settings",
      line: "Get and set any config option without opening the file.",
      body: "config.options lists each option with its type. config.get reads one value. config.set changes a value and loads the config again. reload loads catwm.conf again after you edit it.",
      cli: [
        "catwm config.options",
        "catwm config.get animate",
        "catwm config.set animate false",
        "catwm reload",
      ],
    },
    {
      id: "cli-limits",
      name: "What the socket refuses",
      line: "exec and launch work only from a bind.",
      body: "The socket does not accept exec and launch, so a script cannot run shell commands or open apps through CatWM. Put them in a bind line. There is no catwm:// URL scheme for the same reason.",
      config: [
        "bind = $mod, return, exec, open -a Terminal",
        "bind = $mod, b, launch, Safari workspace=2",
      ],
    },
  ],
};

const EVENTS: Category = {
  id: "agent-events",
  name: "Events",
  hue: "magenta",
  features: [
    {
      id: "events",
      name: "Listen for changes",
      line: "One line for each change, as it happens.",
      body: "catwm events prints the events that you name, or all of them. The events are focus.changed, window.added, window.removed, workspace.changed, layout.changed, tiling.changed, mode.changed, window.notifications and config.reloaded. On a socket connection, send subscribe and unsubscribe.",
      cli: ["catwm events focus.changed workspace.changed", "catwm events"],
    },
  ],
};

const CLIENTS: Category = {
  id: "agent-clients",
  name: "Clients",
  hue: "lemon",
  features: [
    {
      id: "python",
      name: "Python",
      line: "catwm-client for Python 3.10 and later, with no dependencies.",
      body: "Add Clients/python to PYTHONPATH, or install it with pip. Each command is a method, and call(name, args) runs any command by name.",
      media: code(
        "Python",
        `from catwm import CatWM

with CatWM() as catwm:
    catwm.workspace("2")
    print(catwm.windows())

for event in CatWM.events("focus.changed"):
    print(event["data"])`,
      ),
    },
    {
      id: "typescript",
      name: "TypeScript",
      line: "catwm-client for Node 18 and later.",
      body: "Run npm install and npm run build in Clients/typescript. Each command is a typed method that returns a promise.",
      media: code(
        "TypeScript",
        `import { CatWM } from "catwm-client";

const catwm = await CatWM.connect();
await catwm.movefocus("left");
for await (const event of catwm.events("focus.changed"))
  console.log(event.data);`,
      ),
    },
    {
      id: "swift",
      name: "Swift",
      line: "The CatWMClient package.",
      body: "Add Clients/swift as a package dependency. Each command is a method with typed arguments.",
      media: code(
        "Swift",
        `import CatWMClient

let catwm = try CatWM()
try catwm.movefocus(direction: .left)
for try await event in CatWM.events(["focus.changed"]) {
    print(event)
}`,
      ),
    },
    {
      id: "schema",
      name: "Schema",
      line: "One JSON file that describes each command and event.",
      body: "The three clients are generated from Clients/schema.json. Read it to learn the arguments and the result of each command, or to make a client for another language.",
    },
  ],
};

const FILES: Category = {
  id: "agent-files",
  name: "Files",
  hue: "sky",
  features: [
    {
      id: "config-file",
      name: "Config file",
      line: "One text file with Hyprland-style binds.",
      body: "CatWM reads ~/.config/catwm/catwm.conf. The Settings window changes the same file. Bind lines use the Hyprland syntax, with ranges such as 1..0, lists such as h|j|k|l, variables and your own modes. Run catwm reload, or press Shift R in window mode, to load it again.",
      keys: [["⇧", "R"]],
      cli: ["catwm reload", "catwm config.set animate false"],
      media: code(
        "catwm.conf",
        `$mod = ALT
layouts = bsp, wide, floating, fullscreen
window-margin-size = 10

bind = SUPER, capslock, submap, window
bind = CTRL, 1..0, workspace, 1..10
bind = $mod, tab, switcher`,
      ),
    },
    {
      id: "bind-syntax",
      name: "Bind lines",
      line: "MODS, key, command, arguments.",
      body: "A bind line is bind = MODS, key, command, arguments. A range such as 1..0 or a list such as h|j|k|l makes one bind for each key. submap = name starts your own mode, and binds after it belong to that mode. Scroll and swipe keys are mouse_up, mouse_down, swipe_left and swipe_right.",
      media: code(
        "catwm.conf",
        `submap = window
bind = , h|j|k|l, movefocus, l|d|u|r
bind = SHIFT, 1..0, movetoworkspace, 1..10
bind = , escape, submap, reset
submap = reset`,
      ),
    },
    {
      id: "launch-options",
      name: "Launch options",
      line: "Edit how each saved window opens.",
      body: "In templates.json, each window can have a URL, arguments or a command. CatWM uses it when it opens the window.",
      media: code(
        "templates.json",
        `"launch": {
  "url": "https://github.com",
  "arguments": ["--new-window"]
}`,
      ),
    },
  ],
};

// One row for each user category: every command and config line behind it.
const REFERENCE: Category = {
  id: "agent-reference",
  name: "Reference",
  hue: "lime",
  features: USER.map((c) => ({
    id: `reference-${c.id}`,
    name: c.name,
    line: `The commands and options of ${c.name.toLowerCase()}.`,
    body: `Each command and config line behind the ${c.name.toLowerCase()} features above.`,
    cli: [...new Set(c.features.flatMap((f) => f.cli ?? []))],
    config: [...new Set(c.features.flatMap((f) => f.config ?? []))],
  })).filter((f) => f.cli.length + f.config.length > 0),
};

export const AGENT: Category[] = [GUIDE, CLI, EVENTS, CLIENTS, FILES, REFERENCE];
