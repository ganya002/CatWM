// The types of catwm.config.ts. CatWM writes this file each time it starts, so don't edit it.
// Your config: `import type { Config } from "./catwm"`, then `export default { … } satisfies Config`.

export type Mod = "cmd" | "alt" | "ctrl" | "shift"

export type Key =
  | "a"
  | "s"
  | "d"
  | "f"
  | "h"
  | "g"
  | "z"
  | "x"
  | "c"
  | "v"
  | "section"
  | "b"
  | "q"
  | "w"
  | "e"
  | "r"
  | "y"
  | "t"
  | "1"
  | "2"
  | "3"
  | "4"
  | "6"
  | "5"
  | "equal"
  | "9"
  | "7"
  | "minus"
  | "8"
  | "0"
  | "bracketright"
  | "o"
  | "u"
  | "bracketleft"
  | "i"
  | "p"
  | "return"
  | "l"
  | "j"
  | "apostrophe"
  | "k"
  | "semicolon"
  | "backslash"
  | "comma"
  | "slash"
  | "n"
  | "m"
  | "period"
  | "tab"
  | "space"
  | "grave"
  | "backspace"
  | "escape"
  | "capslock"
  | "yen"
  | "underscore_jis"
  | "f5"
  | "f6"
  | "f7"
  | "f3"
  | "f8"
  | "f9"
  | "eisu"
  | "f11"
  | "kana"
  | "f10"
  | "f12"
  | "home"
  | "pageup"
  | "delete"
  | "f4"
  | "end"
  | "f2"
  | "pagedown"
  | "f1"
  | "left"
  | "right"
  | "down"
  | "up"
  | "mouse_up"
  | "mouse_down"
  | "mouse_left"
  | "mouse_right"
  | "swipe_left"
  | "swipe_right"
  | "swipe_up"
  | "swipe_down"

export type Layout = "tall" | "tall-right" | "wide" | "middle-wide" | "fullscreen" | "column" | "row" | "floating" | "bsp" | "3column-left" | "3column-middle" | "3column-right" | "two-pane" | "two-pane-right" | "widescreen-tall" | "widescreen-tall-right"

/** Each action and its arguments. Binds pass the arguments as the `.conf` file did. */
export interface Actions {
  /** Focus the window next to the focused window. */
  movefocus: [direction: "left" | "right" | "up" | "down" | "l" | "r" | "u" | "d" | (string & {})]
  /** Focus the next or previous window. */
  cyclenext: [step?: "next" | "prev" | (string & {})]
  /** Focus a display. */
  focusmonitor: [target: "+1" | "-1" | "l" | "r" | "u" | "d" | (string & {})]
  /** Move the focused window in a direction. */
  movewindow: [direction: "left" | "right" | "up" | "down" | "l" | "r" | "u" | "d" | "mon:-1" | "mon:l" | "mon:r" | "mon:u" | "mon:d" | (string & {})]
  /** Move the focused window to another display. */
  movewindowtomonitor: [target: string | number]
  /** Swap the focused window with its neighbour. */
  swapwindow: [direction: "left" | "right" | "up" | "down" | (string & {})]
  /** Swap the focused window with the next or previous window. */
  swapnext: [step?: "next" | "prev" | (string & {})]
  /** Float or tile the focused window. */
  togglefloating: [...args: (string | number)[]]
  /** Fill the screen with the focused window, inside the tiling. */
  fullscreen: [...args: (string | number)[]]
  /** Give the focused window a macOS full screen Desktop. */
  nativefullscreen: [...args: (string | number)[]]
  /** Minimise the focused window. */
  minimize: [...args: (string | number)[]]
  /** Close the focused window. */
  killactive: [...args: (string | number)[]]
  /** Add the focused window to the tabs of its neighbour. */
  moveintogroup: [direction: "left" | "right" | "up" | "down" | "l" | "r" | "u" | "d" | (string & {})]
  /** Take the focused window out of its tabs. */
  moveoutofgroup: [...args: (string | number)[]]
  /** Show another tab. */
  changegroupactive: [tab?: "f" | "b" | (string & {})]
  /** Move the focused tab along the strip. */
  movegroupwindow: [step?: "next" | "prev" | "f" | "b" | (string & {})]
  /** Send a message to the layout. */
  layoutmsg: [message: "focusmaster" | "swapsides" | "addmaster" | "removemaster" | (string & {})]
  /** Change the size of the main pane. */
  splitratio: [value: "+0.05" | "-0.05" | (string & {})]
  /** Use the next or previous layout. */
  cyclelayout: [step?: "next" | "prev" | (string & {})]
  /** Use a layout on the current screen. */
  layout: [layout: "tall" | "tall-right" | "wide" | "middle-wide" | "fullscreen" | "column" | "row" | "floating" | "bsp" | "3column-left" | "3column-middle" | "3column-right" | "two-pane" | "two-pane-right" | "widescreen-tall" | "widescreen-tall-right" | (string & {})]
  /** Use a layout on the current screen. */
  setlayout: [layout: "tall" | "tall-right" | "wide" | "middle-wide" | "fullscreen" | "column" | "row" | "floating" | "bsp" | "3column-left" | "3column-middle" | "3column-right" | "two-pane" | "two-pane-right" | "widescreen-tall" | "widescreen-tall-right" | (string & {})]
  /** Turn tiling on or off. */
  toggletiling: [...args: (string | number)[]]
  toggledim: []
  toggleblur: []
  /** Place every window again. */
  retile: [...args: (string | number)[]]
  /** Place every window again. */
  reevaluate: [...args: (string | number)[]]
  /** Show a workspace. */
  workspace: [workspace: "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "10" | "previous" | "+1" | "-1" | "e+1" | (string & {})]
  /** Move the focused window to a workspace and go there. */
  movetoworkspace: [workspace: "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "10" | (string & {})]
  /** Move the focused window to a workspace and stay. */
  movetoworkspacesilent: [workspace: "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "10" | (string & {})]
  /** Make the current Desktop the home Desktop. */
  sethomespace: [...args: (string | number)[]]
  /** Open or close the Overview. */
  sort: [...args: (string | number)[]]
  /** Undo the last Overview change. */
  "sort-undo": [...args: (string | number)[]]
  /** Open the window switcher. */
  switcher: [step?: "next" | "prev" | (string & {})]
  /** Enter a key mode, or leave it. */
  submap: [name: "window" | "reset" | (string & {})]
  /** Read the config file again. */
  reload: [...args: (string | number)[]]
  /** Quit CatWM. */
  exit: [...args: (string | number)[]]
  /** Run a shell command. */
  exec: [...args: (string | number)[]]
  /** Open an app, file, URL or command. */
  launch: [...args: (string | number)[]]
}

/** An action name, or the name and its arguments: `"sort"` or `["workspace", "2"]`. */
export type Action = {
  [A in keyof Actions]: [] extends Actions[A] ? A | [A, ...Actions[A]] : [A, ...Actions[A]]
}[keyof Actions]

export interface Bind {
  /** The modifiers you hold with the key. */
  mods?: readonly Mod[]
  key: Key
  run: Action
  /** Run the action again while you hold the key. */
  repeat?: boolean
}

export interface Config {
  animation?: {
    /** Bounciness. How far springs swing, balls bounce and overshoot goes. From 0 to 1. Default: `0.5`. */
    bounce?: number
    /** Curve. How windows speed up and settle. Default: `ease-out`. */
    curve?: "ease-out" | "ease-in-out" | "linear" | "spring" | "bounce" | "overshoot" | `cubic-bezier(${number}, ${number}, ${number}, ${number})`
    /** Duration. From 0 to 5. Default: `0.12`. */
    duration?: number
    /** Animate windows. Windows glide to their new place. Default: `true`. */
    enabled?: boolean
  }
  /** The binds that work in every app. */
  binds?: readonly Bind[]
  /** Quick actions at the pointer. In window mode, tap the mode's modifier to save or open a workspace template. Default: `true`. */
  cursorActions?: boolean
  /** Verbose log; prefer `--verbose`. Default: `false`. */
  debugLogging?: boolean
  features?: {
    input?: {
      /** Quick actions at the pointer in window mode. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      cursorActions?: boolean
      /** Switch workspaces with trackpad swipes. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      gestures?: boolean
      /** Read key presses for the binds. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      keys?: boolean
      /** Swap and resize windows with the mouse, and pull windows from the Dock. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      mouse?: boolean
    }
    presentation?: {
      /** Dim and blur the other windows. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      dimming?: boolean
      /** The layout and config messages. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      hud?: boolean
      /** The keyboard help in window mode. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      keyHelp?: boolean
      /** The Overview of every workspace. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      overview?: boolean
      /** The window switcher. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      switcher?: boolean
      /** The tab strip above a tab group. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      tabStrips?: boolean
    }
    services?: {
      /** Unread badges on tabs. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      notifications?: boolean
      /** Save and open app windows, tabs and folders. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      sessions?: boolean
      /** The control socket for the CLI and the libraries. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      socket?: boolean
      /** Saved workspace templates. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      templates?: boolean
    }
    windows?: {
      /** Run each workspace as a macOS Desktop. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      desktops?: boolean
      /** Group windows as tabs. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      tabGroups?: boolean
      /** Lay out windows with the layouts. Embedded mode reads this. Standalone CatWM keeps every feature on for now. */
      tiling?: boolean
    }
  }
  floating?: {
    /** Bundle IDs of the apps that float. `com.adobe.*` matches every Adobe app. */
    apps?: readonly string[]
    /** Apps in the list. True: listed apps float. false: only listed apps are tiled. Default: `true`. */
    listedAppsFloat?: boolean
    /** Float small windows. Dialogs and panels stay put. Default: `true`. */
    smallWindows?: boolean
  }
  focus?: {
    /** Focus follows mouse. Hovering a window focuses it. Default: `true`. */
    followsMouse?: boolean
    /** Only in window mode. Hovering focuses a window only while window mode is on. Default: `true`. */
    followsMouseInModeOnly?: boolean
    /** Mouse follows focus. The pointer jumps to the window you focus. Default: `true`. */
    mouseFollowsFocus?: boolean
  }
  focusDim?: {
    /** Blur other windows. Softens everything but the focused window. Default: `false`. */
    blur?: boolean
    /** Blur radius. How soft the other windows look. From 1 to 100. Default: `20`. */
    blurRadius?: number
    /** Dim other windows. Darkens everything but the focused window. Default: `false`. */
    dim?: boolean
    /** Dim strength. How dark the other windows get. From 0 to 1. Default: `0.5`. */
    dimStrength?: number
  }
  gaps?: {
    /** Gaps between windows. Gaps between windows. Default: `true`. */
    enabled?: boolean
    /** Gap size. `gaps_in` is accepted and doubled. From 0 to 100. Default: `10`. */
    size?: number
    /** Smart gaps. No gaps when a window is alone. Default: `true`. */
    smart?: boolean
  }
  /** Ignore menu bar when tiling. Use this if you hide the menu bar. Default: `false`. */
  ignoreMenuBar?: boolean
  keyboardHelp?: {
    /** Show keyboard help. On-screen keyboard help in window mode. Default: `true`. */
    enabled?: boolean
    /** Keyboard finish. Used by keyboard help and Shortcut Map. Default: `auto`. */
    finish?: "auto" | "macbook-pro" | "macbook-air" | "macbook-neo" | "magic-keyboard" | (string & {})
    /** Toggles the keyboard help in window mode. Default: `?`. */
    key?: string
  }
  layoutHud?: {
    /** Show layout name on change. A short card in the middle of the screen. Default: `false`. */
    enabled?: boolean
    /** Also when switching spaces. Default: `true`. */
    onSpaceChange?: boolean
  }
  /** The layouts that `cyclelayout` steps through, each one once. */
  layouts?: readonly Layout[]
  /** Your main modifier. Window mode and the pointer actions use it. The default is `alt`. */
  mod?: Mod | readonly Mod[]
  /** Window mode effect. Shown at the screen edges while window mode is on. Default: `draw`. */
  modeEffect?: "draw" | "ripple" | "corners" | "none"
  mouse?: {
    /** Drag window edges to resize the main pane. Resize a tiled window with the mouse, and the main pane follows. Default: `true`. */
    resizesWindows?: boolean
    /** Split handle. Drag the bar between the sides to resize. Click it to swap the sides. Default: `true`. */
    splitHandle?: boolean
    /** Drag to swap. Drop a window on another to trade places. Default: `true`. */
    swapsWindows?: boolean
  }
  /** New windows become main. Default: `false`. */
  newWindowsToMain?: boolean
  /** No padding on the built-in display. Default: `true`. */
  noPaddingOnBuiltinDisplay?: boolean
  /** Space between the screen edges and the windows. A number sets all four sides. */
  padding?: number | {
    /** From 0 to 500. Default: `10`. */
    bottom?: number
    /** `screen-padding` or `gaps_out` sets all four sides. From 0 to 500. Default: `10`. */
    left?: number
    /** From 0 to 500. Default: `10`. */
    right?: number
    /** From 0 to 500. Default: `10`. */
    top?: number
  }
  /** Panel animation. How Overview and keyboard help come and go. Default: `rise`. */
  panelAnimation?: "rise" | "pop" | "focus" | "tile" | "draw"
  /** Sends repeated slow animations and hangs (numbers and app bundle IDs only) to the developers. Default: `false`. */
  perfReports?: boolean
  /** Main pane resize step. How much the split moves each time. Default: `5`. */
  resizeStep?: number
  /** Key modes. `["submap", "window"]` enters one and `["submap", "reset"]` leaves it. */
  submaps?: Record<string, readonly Bind[]>
  switcher?: {
    /** Apps the switcher hides. Apps the window switcher never shows; wildcards like com.adobe.* work. Default: `[]`. */
    exclude?: readonly string[]
    /** Instant jump. A search with one prefix match opens by itself. Default: `true`. */
    instantJump?: boolean
    /** Jump delay. 0 opens the match at once. From 0 to 2000. Default: `300`. */
    jumpDelay?: number
  }
  tabs?: {
    /** Auto-hide tab strip. Tab groups hide their tabs. Move the pointer to the window top to show them. Default: `false`. */
    autoHideStrip?: boolean
    /** Show notification badges on tabs. A tab shows the unread count of its app or window. Default: `true`. */
    notificationBadges?: boolean
  }
  /** Save tabs and folders. Browser tabs, terminal tabs, Finder folders and editor projects. macOS asks once for each app. Default: `false`. */
  templateAppScripting?: boolean
  workspaces?: {
    /** Number workspaces on each display. Each display starts at workspace 1. Off: all displays share one set of numbers. Default: `true`. */
    perDisplay?: boolean
    /** Remove empty workspaces when you leave them. Removes the empty Desktop too. Default: `true`. */
    removeEmpty?: boolean
    /** Suggest Overview for a crowded workspace. A tip under the menu bar icon, at most once a day. From 0 to 100. Default: `5`. */
    sortNudge?: number
    /** Stay on this workspace when closing a window. Default: `true`. */
    stayAfterClose?: boolean
    /** Control macOS Desktops with CatWM. CatWM controls workspace keys, animation and Overview. Default: `true`. */
    virtual?: boolean
  }
}
