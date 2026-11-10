// PROTOTYPE for #342, candidate A: one default-exported typed object.
// The whole config is data. `satisfies Config` gives completion and checks every value.
//
// HMR: the config is one module. On save CatWM evaluates it again and diffs the new object
// against the last one by path, so `gaps.size` re-tiles and `submaps.window` re-installs
// only that mode's binds. A helper file it imports is its own module and swaps by itself.
// Trade-offs: closest to today's .conf and to what Settings can write back; no logic needed.
// Chords are object keys, so they are checked on load, not in the editor.

import type { Config } from "catwm"

export default {
  mod: "alt",
  layouts: ["bsp", "wide", "floating", "fullscreen"],

  floating: {
    apps: ["com.apple.systempreferences", "com.apple.SystemSettings", "com.apple.calculator"],
    listed: "float",
    smallWindows: true,
  },

  gaps: { enabled: true, size: 10, smart: true },
  padding: 10,
  noPaddingOnBuiltinDisplay: true,
  ignoreMenuBar: false,

  focus: { mouseFollowsFocus: true, followsMouse: true, followsMouseInModeOnly: true },
  mouse: { swapsWindows: true, resizesWindows: true, splitHandle: true },
  tabs: { autoHideStrip: false, notificationBadges: true },
  newWindowsToMain: false,
  resizeStep: 0.05,
  layoutHud: { enabled: false, onSpaceChange: true },
  focusDim: { dim: false, dimStrength: 0.5, blur: false, blurRadius: 20 },

  workspaces: { virtual: true, stayAfterClose: true, removeEmpty: true, perDisplay: true, sortNudge: 5 },
  keyboardHelp: { enabled: true, key: "?", finish: "auto" },
  cursorActions: true,
  templateAppScripting: false,
  switcher: { instantJump: true, jumpDelay: 300, exclude: [] },

  animation: { enabled: true, duration: 0.12, curve: "ease-out", bounce: 0.5 },
  panelAnimation: "rise",
  modeEffect: "draw",

  // Global binds work everywhere. Everything else lives in window mode.
  binds: {
    "ctrl 1..0": ["workspace", "1..10"],
    "ctrl left|right": ["workspace", "r-1|r+1"],
    "ctrl shift 1..0": ["movetoworkspace", "1..10"],
    "ctrl shift left|right": ["movetoworkspace", "r-1|r+1"],
    "$mod o": "sort",
    // Tap for the last window, hold to browse every window, type to search:
    "$mod tab": "switcher",
    "$mod shift tab": ["switcher", "prev"],
    "cmd capslock": ["submap", "window"],
    // Control+Option works in every app, outside window mode:
    "$mod ctrl h|j|k|l": ["movefocus", "l|d|u|r"],
    "$mod ctrl shift h|j|k|l": ["movewindow", "l|d|u|r"],
    "$mod ctrl f": "fullscreen",
    "$mod ctrl v": "togglefloating",
    // Scroll and swipes while holding the modifier:
    // "$mod mouse_down": ["workspace", "e+1"],
    // "$mod mouse_up": ["workspace", "e-1"],
    // "$mod ctrl swipe_left": ["workspace", "e+1"],
  },

  submaps: {
    window: {
      "h|j|k|l": ["movefocus", "l|d|u|r"],
      "left|down|up|right": ["movefocus", "l|d|u|r"],
      "shift h|j|k|l": ["movewindow", "l|d|u|r"],
      "shift left|down|up|right": ["movewindow", "l|d|u|r"],
      "1..0": ["workspace", "1..10"],
      "shift 1..0": ["movetoworkspace", "1..10"],
      "w": ["focusmonitor", "+1"],
      "b": ["focusmonitor", "-1"],
      "shift w": ["movewindow", "mon:+1"],
      "shift b": ["movewindow", "mon:-1"],
      "n": ["cyclelayout", "next"],
      "p": ["cyclelayout", "prev"],
      "comma": ["splitratio", "-0.05"],
      "period": ["splitratio", "+0.05"],
      "shift comma": ["layoutmsg", "addmaster"],
      "shift period": ["layoutmsg", "removemaster"],
      "m": ["layoutmsg", "swapwithmaster"],
      "shift m": ["layoutmsg", "swapsides"],
      "g": ["layoutmsg", "focusmaster"],
      "s": ["layoutmsg", "orientationnext"],
      "shift s": ["layoutmsg", "orientationprev"],
      "tab": "cyclenext",
      "shift tab": ["cyclenext", "prev"],
      "ctrl h|j|k|l": ["moveintogroup", "l|d|u|r"],
      "t": "moveoutofgroup",
      "bracketleft|bracketright": ["changegroupactive", "b|f"],
      "shift bracketleft|bracketright": ["movegroupwindow", "b|f"],
      "f": "fullscreen",
      "shift f": "nativefullscreen",
      "v": "togglefloating",
      "z": "retile",
      "shift t": "toggletiling",
      "shift r": "reload",
      "o": "sort",
      "slash": "switcher",
      "grave": ["workspace", "previous"],
      "x": "killactive",
      "minus": "minimize",
      "d": "toggledim",
      "shift d": "toggleblur",
      "escape|i|return": ["submap", "reset"],
      "cmd capslock": ["submap", "reset"],
    },
  },
} satisfies Config
