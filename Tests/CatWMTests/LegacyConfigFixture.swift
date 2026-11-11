let legacyUserConfig = #"""
// CatWM config, converted from catwm.conf.
// catwm.conf stays next to it as a backup that CatWM no longer reads.
// Types and completion come from catwm.d.ts. Save the file and CatWM applies the change.
import type { Config } from "./catwm"

// CatWM config: Amethyst's options with Hyprland-style syntax.
// Edit, then reload from the menu bar or with $mod SHIFT, R.
// SUPER = Command, ALT = Option. Option is the default so app shortcuts (Cmd-Q, Cmd-C...) keep working.
const mod = "alt"

export default {
  mod,
  // ---- layouts ---------------------------------------------------------------
  // tall, tall-right, wide, middle-wide, fullscreen, column, row, floating, bsp, 3column-left,
  // 3column-middle, 3column-right, two-pane, two-pane-right, widescreen-tall, widescreen-tall-right
  layouts: ["bsp", "wide", "floating", "fullscreen"],
  floating: {
    // ---- floating apps ---------------------------------------------------------
    // Bundle IDs to float (wildcards like com.adobe.* work). Set floating-is-blacklist = false
    // to make this a list of the ONLY apps that get tiled.
    apps: ["com.apple.systempreferences", "com.apple.SystemSettings", "com.apple.calculator"],
    listedAppsFloat: true,
    smallWindows: true,
  },
  gaps: {
    // ---- gaps ------------------------------------------------------------------
    // Hyprland names also work: gaps_in = per-window gap, gaps_out = screen padding.
    enabled: true,
    size: 10,
    smart: true,
  },
  padding: {
    left: 10,
    right: 10,
    top: 10,
    bottom: 10,
  },
  noPaddingOnBuiltinDisplay: true,
  ignoreMenuBar: false,
  focus: {
    // ---- behaviour -------------------------------------------------------------
    mouseFollowsFocus: true,
    followsMouse: true,
    // With focus-follows-mouse on: hovering focuses a window only while window mode is on.
    followsMouseInModeOnly: true,
  },
  mouse: {
    swapsWindows: true,
    resizesWindows: true,
    splitHandle: true,
  },
  tabs: {
    autoHideStrip: false,
    notificationBadges: true,
  },
  newWindowsToMain: false,
  // How far the main pane grows or shrinks each time, in percent (5) or as a fraction (0.05).
  resizeStep: 0.05,
  layoutHud: {
    enabled: false,
    onSpaceChange: true,
  },
  focusDim: {
    // ---- focused window --------------------------------------------------------
    // Make the focused window stand out: darken the others (strength 0-1) and/or blur them (radius in points).
    dim: false,
    dimStrength: 0.5,
    blur: false,
    blurRadius: 20,
  },
  workspaces: {
    // ---- workspaces ------------------------------------------------------------
    // CatWM controls native Desktops, workspace keys, animation and Overview.
    virtual: true,
    stayAfterClose: true,
    removeEmpty: true,
    perDisplay: true,
    sortNudge: 5,
  },
  keyboardHelp: {
    // ---- keyboard help ---------------------------------------------------------
    // Keep holding the window-mode chord's modifier (or press keyboard-help-key in window mode) to see
    // every window-mode key on an on-screen keyboard.
    enabled: true,
    key: "?",
    // The keyboard drawn there and in Settings: auto follows this Mac (model, colour, layout). Or pick a model
    // (macbook-pro, macbook-air, macbook-neo, magic-keyboard) or a finish, e.g. macbook-pro-space-black,
    // macbook-air-midnight, macbook-air-starlight, macbook-neo-citrus, imac-blue.
    finish: "auto",
  },
  // In window mode a dot follows the pointer; tap the mode's modifier to save or open workspace templates.
  cursorActions: true,
  // ---- templates -------------------------------------------------------------
  // Templates also save browser tabs, terminal folders, Finder folders and editor projects.
  // macOS asks you once for each app to let CatWM control it.
  templateAppScripting: false,
  switcher: {
    // ---- window switcher -------------------------------------------------------
    // The window switcher: tap $mod Tab for the last window, hold it to browse, type to search.
    // Instant jump opens a search with one prefix match by itself after the delay (0 opens it at once).
    instantJump: true,
    jumpDelay: 300,
    // Bundle IDs the switcher never shows, comma separated (wildcards like com.adobe.* work).
    exclude: [],
  },
  animation: {
    // ---- animation -------------------------------------------------------------
    // These also set how windows slide when you switch workspaces.
    enabled: true,
    // Seconds; a value above 5 is read as milliseconds.
    duration: 0.12,
    // ease-out, ease-in-out, linear, spring, bounce, overshoot or cubic-bezier(x1, y1, x2, y2)
    // like CSS (y past 0...1 overshoots).
    curve: "ease-out",
    // How lively spring, bounce and overshoot are, 0-1.
    bounce: 0.5,
  },
  // ---- panels and window mode ------------------------------------------------
  // How Overview and keyboard help come and go: rise, pop, focus, tile or draw.
  panelAnimation: "rise",
  // The screen-edge effect while window mode is on: draw, ripple, corners or none.
  modeEffect: "draw",
  // ---- diagnostics -----------------------------------------------------------
  debugLogging: false,
  // Send repeated animation slowdowns and hangs (numbers and app IDs only) to the developers.
  perfReports: false,
  binds: [
    // ---- keybinds: bind = MODS, key, dispatcher, args -------------------------
    // Global binds work everywhere. Everything else lives in "window mode" (a Hyprland submap):
    // press Cmd+Caps Lock, then single keys, vim style. Esc / i / Return or a mouse click leaves it.
    { mods: ["ctrl"], key: "1", run: ["workspace", "1"] },
    { mods: ["ctrl"], key: "2", run: ["workspace", "2"] },
    { mods: ["ctrl"], key: "3", run: ["workspace", "3"] },
    { mods: ["ctrl"], key: "4", run: ["workspace", "4"] },
    { mods: ["ctrl"], key: "5", run: ["workspace", "5"] },
    { mods: ["ctrl"], key: "6", run: ["workspace", "6"] },
    { mods: ["ctrl"], key: "7", run: ["workspace", "7"] },
    { mods: ["ctrl"], key: "8", run: ["workspace", "8"] },
    { mods: ["ctrl"], key: "9", run: ["workspace", "9"] },
    { mods: ["ctrl"], key: "0", run: ["workspace", "10"] },
    { mods: ["ctrl"], key: "left", run: ["workspace", "r-1"] },
    { mods: ["ctrl"], key: "right", run: ["workspace", "r+1"] },
    { mods: ["ctrl", "shift"], key: "1", run: ["movetoworkspace", "1"] },
    { mods: ["ctrl", "shift"], key: "2", run: ["movetoworkspace", "2"] },
    { mods: ["ctrl", "shift"], key: "3", run: ["movetoworkspace", "3"] },
    { mods: ["ctrl", "shift"], key: "4", run: ["movetoworkspace", "4"] },
    { mods: ["ctrl", "shift"], key: "5", run: ["movetoworkspace", "5"] },
    { mods: ["ctrl", "shift"], key: "6", run: ["movetoworkspace", "6"] },
    { mods: ["ctrl", "shift"], key: "7", run: ["movetoworkspace", "7"] },
    { mods: ["ctrl", "shift"], key: "8", run: ["movetoworkspace", "8"] },
    { mods: ["ctrl", "shift"], key: "9", run: ["movetoworkspace", "9"] },
    { mods: ["ctrl", "shift"], key: "0", run: ["movetoworkspace", "10"] },
    { mods: ["ctrl", "shift"], key: "left", run: ["movetoworkspace", "r-1"] },
    { mods: ["ctrl", "shift"], key: "right", run: ["movetoworkspace", "r+1"] },
    { mods: [mod], key: "o", run: "sort" },
    // Tap for the last window, hold to browse every window, type to search:
    { mods: [mod], key: "tab", run: "switcher" },
    { mods: [mod, "shift"], key: "tab", run: ["switcher", "prev"] },
    { mods: ["cmd"], key: "capslock", run: ["submap", "window"] },
    // Control+Option works in every app, outside window mode:
    { mods: [mod, "ctrl"], key: "h", run: ["movefocus", "l"] },
    { mods: [mod, "ctrl"], key: "j", run: ["movefocus", "d"] },
    { mods: [mod, "ctrl"], key: "k", run: ["movefocus", "u"] },
    { mods: [mod, "ctrl"], key: "l", run: ["movefocus", "r"] },
    { mods: [mod, "ctrl", "shift"], key: "h", run: ["movewindow", "l"] },
    { mods: [mod, "ctrl", "shift"], key: "j", run: ["movewindow", "d"] },
    { mods: [mod, "ctrl", "shift"], key: "k", run: ["movewindow", "u"] },
    { mods: [mod, "ctrl", "shift"], key: "l", run: ["movewindow", "r"] },
    { mods: [mod, "ctrl"], key: "f", run: "fullscreen" },
    { mods: [mod, "ctrl"], key: "v", run: "togglefloating" },
  ],
  submaps: {
    window: [
      // Scroll wheel / trackpad scroll while holding the modifier, and trackpad swipes:
      // bind = $mod, mouse_down, workspace, e+1
      // bind = $mod, mouse_up, workspace, e-1
      // bind = $mod CTRL, swipe_left, workspace, e+1
      { key: "h", run: ["movefocus", "l"] },
      { key: "j", run: ["movefocus", "d"] },
      { key: "k", run: ["movefocus", "u"] },
      { key: "l", run: ["movefocus", "r"] },
      { key: "left", run: ["movefocus", "l"] },
      { key: "down", run: ["movefocus", "d"] },
      { key: "up", run: ["movefocus", "u"] },
      { key: "right", run: ["movefocus", "r"] },
      { mods: ["shift"], key: "h", run: ["movewindow", "l"] },
      { mods: ["shift"], key: "j", run: ["movewindow", "d"] },
      { mods: ["shift"], key: "k", run: ["movewindow", "u"] },
      { mods: ["shift"], key: "l", run: ["movewindow", "r"] },
      { mods: ["shift"], key: "left", run: ["movewindow", "l"] },
      { mods: ["shift"], key: "down", run: ["movewindow", "d"] },
      { mods: ["shift"], key: "up", run: ["movewindow", "u"] },
      { mods: ["shift"], key: "right", run: ["movewindow", "r"] },
      { key: "1", run: ["workspace", "1"] },
      { key: "2", run: ["workspace", "2"] },
      { key: "3", run: ["workspace", "3"] },
      { key: "4", run: ["workspace", "4"] },
      { key: "5", run: ["workspace", "5"] },
      { key: "6", run: ["workspace", "6"] },
      { key: "7", run: ["workspace", "7"] },
      { key: "8", run: ["workspace", "8"] },
      { key: "9", run: ["workspace", "9"] },
      { key: "0", run: ["workspace", "10"] },
      { mods: ["shift"], key: "1", run: ["movetoworkspace", "1"] },
      { mods: ["shift"], key: "2", run: ["movetoworkspace", "2"] },
      { mods: ["shift"], key: "3", run: ["movetoworkspace", "3"] },
      { mods: ["shift"], key: "4", run: ["movetoworkspace", "4"] },
      { mods: ["shift"], key: "5", run: ["movetoworkspace", "5"] },
      { mods: ["shift"], key: "6", run: ["movetoworkspace", "6"] },
      { mods: ["shift"], key: "7", run: ["movetoworkspace", "7"] },
      { mods: ["shift"], key: "8", run: ["movetoworkspace", "8"] },
      { mods: ["shift"], key: "9", run: ["movetoworkspace", "9"] },
      { mods: ["shift"], key: "0", run: ["movetoworkspace", "10"] },
      { key: "w", run: ["focusmonitor", "+1"] },
      { key: "b", run: ["focusmonitor", "-1"] },
      { mods: ["shift"], key: "w", run: ["movewindow", "mon:+1"] },
      { mods: ["shift"], key: "b", run: ["movewindow", "mon:-1"] },
      { key: "n", run: ["cyclelayout", "next"] },
      { key: "p", run: ["cyclelayout", "prev"] },
      { key: "comma", run: ["splitratio", "-0.05"] },
      { key: "period", run: ["splitratio", "+0.05"] },
      { mods: ["shift"], key: "comma", run: ["layoutmsg", "addmaster"] },
      { mods: ["shift"], key: "period", run: ["layoutmsg", "removemaster"] },
      { key: "m", run: ["layoutmsg", "swapwithmaster"] },
      { mods: ["shift"], key: "m", run: ["layoutmsg", "swapsides"] },
      { key: "g", run: ["layoutmsg", "focusmaster"] },
      { key: "s", run: ["layoutmsg", "orientationnext"] },
      { mods: ["shift"], key: "s", run: ["layoutmsg", "orientationprev"] },
      { key: "tab", run: "cyclenext" },
      { mods: ["shift"], key: "tab", run: ["cyclenext", "prev"] },
      { mods: ["ctrl"], key: "h", run: ["moveintogroup", "l"] },
      { mods: ["ctrl"], key: "j", run: ["moveintogroup", "d"] },
      { mods: ["ctrl"], key: "k", run: ["moveintogroup", "u"] },
      { mods: ["ctrl"], key: "l", run: ["moveintogroup", "r"] },
      { key: "t", run: "moveoutofgroup" },
      { key: "bracketleft", run: ["changegroupactive", "b"] },
      { key: "bracketright", run: ["changegroupactive", "f"] },
      { mods: ["shift"], key: "bracketleft", run: ["movegroupwindow", "b"] },
      { mods: ["shift"], key: "bracketright", run: ["movegroupwindow", "f"] },
      { key: "f", run: "fullscreen" },
      { mods: ["shift"], key: "f", run: "nativefullscreen" },
      { key: "v", run: "togglefloating" },
      { key: "z", run: "retile" },
      { mods: ["shift"], key: "t", run: "toggletiling" },
      { mods: ["shift"], key: "r", run: "reload" },
      { key: "o", run: "sort" },
      { key: "slash", run: "switcher" },
      { key: "grave", run: ["workspace", "previous"] },
      { key: "x", run: "killactive" },
      { key: "minus", run: "minimize" },
      { key: "d", run: "toggledim" },
      { mods: ["shift"], key: "d", run: "toggleblur" },
      { key: "escape", run: ["submap", "reset"] },
      { key: "i", run: ["submap", "reset"] },
      { key: "return", run: ["submap", "reset"] },
      { mods: ["cmd"], key: "capslock", run: ["submap", "reset"] },
    ],
  },
} satisfies Config
"""#
