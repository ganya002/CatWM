// PROTOTYPE for #342, candidate C. The options module. Settings would write here.
import { options } from "catwm"

export default options({
  mod: "alt",
  layouts: ["bsp", "wide", "floating", "fullscreen"],

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
})
