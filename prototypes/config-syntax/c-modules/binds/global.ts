// PROTOTYPE for #342, candidate C. Global binds work everywhere.
// Everything else lives in window mode (./window-mode.ts).
import { binds } from "catwm"

export default binds([
  ["ctrl", "1..0", "workspace", "1..10"],
  ["ctrl", "left|right", "workspace", "r-1|r+1"],
  ["ctrl shift", "1..0", "movetoworkspace", "1..10"],
  ["ctrl shift", "left|right", "movetoworkspace", "r-1|r+1"],
  ["$mod", "o", "sort"],
  // Tap for the last window, hold to browse every window, type to search:
  ["$mod", "tab", "switcher"],
  ["$mod shift", "tab", "switcher", "prev"],
  ["cmd", "capslock", "submap", "window"],
  // Control+Option works in every app, outside window mode:
  ["$mod ctrl", "h|j|k|l", "movefocus", "l|d|u|r"],
  ["$mod ctrl shift", "h|j|k|l", "movewindow", "l|d|u|r"],
  ["$mod ctrl", "f", "fullscreen"],
  ["$mod ctrl", "v", "togglefloating"],
  // Scroll and swipes while holding the modifier:
  // ["$mod", "mouse_down", "workspace", "e+1"],
  // ["$mod", "mouse_up", "workspace", "e-1"],
  // ["$mod ctrl", "swipe_left", "workspace", "e+1"],
])
