// PROTOTYPE for #342, candidate B: `defineConfig` with typed chord builders.
// Options are the same data as in A. Binds are written as `mods(keys).dispatcher(args)`,
// so the editor completes the mods, checks the keys and lists every dispatcher with its args.
//
// HMR: still one module, evaluated again on save. Binds are functions, so CatWM calls
// each `binds`/`submaps.*` function again and diffs the Bind lists; a changed mode re-installs alone.
// Trade-offs: best completion and errors while typing, and a host or user can compute binds
// (loops, `defaults`). It reads less like a table, and Settings must write code, not data.

import { defineConfig } from "catwm"

export default defineConfig({
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
  binds: ({ ctrl, cmd, mod }) => [
    ctrl("1..0").workspace("1..10"),
    ctrl("left|right").workspace("r-1|r+1"),
    ctrl.shift("1..0").movetoworkspace("1..10"),
    ctrl.shift("left|right").movetoworkspace("r-1|r+1"),
    mod("o").sort(),
    // Tap for the last window, hold to browse every window, type to search:
    mod("tab").switcher(),
    mod.shift("tab").switcher("prev"),
    cmd("capslock").submap("window"),
    // Control+Option works in every app, outside window mode:
    mod.ctrl("h|j|k|l").movefocus("l|d|u|r"),
    mod.ctrl.shift("h|j|k|l").movewindow("l|d|u|r"),
    mod.ctrl("f").fullscreen(),
    mod.ctrl("v").togglefloating(),
    // Scroll and swipes while holding the modifier:
    // mod("mouse_down").workspace("e+1"),
    // mod("mouse_up").workspace("e-1"),
    // mod.ctrl("swipe_left").workspace("e+1"),
  ],

  submaps: {
    window: ({ none, shift, ctrl, cmd }) => [
      none("h|j|k|l").movefocus("l|d|u|r"),
      none("left|down|up|right").movefocus("l|d|u|r"),
      shift("h|j|k|l").movewindow("l|d|u|r"),
      shift("left|down|up|right").movewindow("l|d|u|r"),
      none("1..0").workspace("1..10"),
      shift("1..0").movetoworkspace("1..10"),
      none("w").focusmonitor("+1"),
      none("b").focusmonitor("-1"),
      shift("w").movewindow("mon:+1"),
      shift("b").movewindow("mon:-1"),
      none("n").cyclelayout("next"),
      none("p").cyclelayout("prev"),
      none("comma").splitratio("-0.05"),
      none("period").splitratio("+0.05"),
      shift("comma").layoutmsg("addmaster"),
      shift("period").layoutmsg("removemaster"),
      none("m").layoutmsg("swapwithmaster"),
      shift("m").layoutmsg("swapsides"),
      none("g").layoutmsg("focusmaster"),
      none("s").layoutmsg("orientationnext"),
      shift("s").layoutmsg("orientationprev"),
      none("tab").cyclenext(),
      shift("tab").cyclenext("prev"),
      ctrl("h|j|k|l").moveintogroup("l|d|u|r"),
      none("t").moveoutofgroup(),
      none("bracketleft|bracketright").changegroupactive("b|f"),
      shift("bracketleft|bracketright").movegroupwindow("b|f"),
      none("f").fullscreen(),
      shift("f").nativefullscreen(),
      none("v").togglefloating(),
      none("z").retile(),
      shift("t").toggletiling(),
      shift("r").reload(),
      none("o").sort(),
      none("slash").switcher(),
      none("grave").workspace("previous"),
      none("x").killactive(),
      none("minus").minimize(),
      none("d").toggledim(),
      shift("d").toggleblur(),
      none("escape|i|return").submap("reset"),
      cmd("capslock").submap("reset"),
    ],
  },
})
