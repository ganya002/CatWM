// The types of catwm.config.ts. CatWM writes this file each time it starts, so don't edit it.
// Your config: `import { catwm } from "./catwm"`, then set options, such as `catwm.gaps.size = 12`.

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

export type Layout = "tall" | "tall-right" | "wide" | "middle-wide" | "fullscreen" | "column" | "row" | "floating" | "bsp" | "dwindle" | "3column-left" | "3column-middle" | "3column-right" | "two-pane" | "two-pane-right" | "widescreen-tall" | "widescreen-tall-right"

/** The motion styles of Settings → Motion. Setting one sets its fields together. */
export type MotionStyle = "none" | "snappy" | "relaxed"

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
  /** Float the focused window. */
  setfloating: [...args: (string | number)[]]
  /** Tile the focused window. */
  settiled: [...args: (string | number)[]]
  /** Resize the focused window. */
  resizeactive: [size: string | number]
  /** Move the focused floating window. */
  moveactive: [position: string | number]
  /** Center the focused floating window on its display. */
  centerwindow: [...args: (string | number)[]]
  /** Keep the focused tiled window at its own size inside its tile. */
  pseudo: [...args: (string | number)[]]
  /** Show the focused floating window on every workspace. */
  pin: [...args: (string | number)[]]
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
  layout: [layout: "tall" | "tall-right" | "wide" | "middle-wide" | "fullscreen" | "column" | "row" | "floating" | "bsp" | "dwindle" | "3column-left" | "3column-middle" | "3column-right" | "two-pane" | "two-pane-right" | "widescreen-tall" | "widescreen-tall-right" | (string & {})]
  /** Use a layout on the current screen. */
  setlayout: [layout: "tall" | "tall-right" | "wide" | "middle-wide" | "fullscreen" | "column" | "row" | "floating" | "bsp" | "dwindle" | "3column-left" | "3column-middle" | "3column-right" | "two-pane" | "two-pane-right" | "widescreen-tall" | "widescreen-tall-right" | (string & {})]
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

/** A list you can change in place: `push`, or `remove` every copy of a value. */
export interface List<T> extends Array<T> {
  remove(value: T): void
}

/** What you can assign to a group: an object that merges, a list that replaces, `undefined` to reset. */
export type Input<T> = {
  [K in keyof T]?: T[K] extends List<infer U> ? readonly U[] | undefined
    : T[K] extends object ? Input<T[K]> | undefined : T[K] | undefined
}

export interface FeaturesInputOptions {
  /** Quick actions at the pointer in window mode. On by default. Embedded mode doesn't have it. */
  get cursorActions(): boolean
  set cursorActions(value: boolean | undefined)
  /** Switch workspaces with trackpad swipes. On by default, off by default in embedded mode. */
  get gestures(): boolean
  set gestures(value: boolean | undefined)
  /** Read key presses for the binds. On by default, off by default in embedded mode. */
  get keys(): boolean
  set keys(value: boolean | undefined)
  /** Swap and resize windows with the mouse, and pull windows from the Dock. On by default, off by default in embedded mode. */
  get mouse(): boolean
  set mouse(value: boolean | undefined)
}

export interface FeaturesPresentationOptions {
  /** Dim and blur the other windows. On by default. Embedded mode doesn't have it. */
  get dimming(): boolean
  set dimming(value: boolean | undefined)
  /** The layout and config messages. On by default. Embedded mode doesn't have it. */
  get hud(): boolean
  set hud(value: boolean | undefined)
  /** The keyboard help in window mode. On by default. Embedded mode doesn't have it. */
  get keyHelp(): boolean
  set keyHelp(value: boolean | undefined)
  /** The Overview of every workspace. On by default. Embedded mode doesn't have it. */
  get overview(): boolean
  set overview(value: boolean | undefined)
  /** The window switcher. On by default. Embedded mode doesn't have it. */
  get switcher(): boolean
  set switcher(value: boolean | undefined)
  /** The tab strip above a tab group. On by default. Embedded mode doesn't have it. */
  get tabStrips(): boolean
  set tabStrips(value: boolean | undefined)
}

export interface FeaturesServicesOptions {
  /** Unread badges on tabs. On by default, off by default in embedded mode. */
  get notifications(): boolean
  set notifications(value: boolean | undefined)
  /** Save and open app windows, tabs and folders. On by default, off by default in embedded mode. */
  get sessions(): boolean
  set sessions(value: boolean | undefined)
  /** The control socket for the CLI and the libraries. On by default, off by default in embedded mode. */
  get socket(): boolean
  set socket(value: boolean | undefined)
  /** Saved workspace templates. On by default, off by default in embedded mode. */
  get templates(): boolean
  set templates(value: boolean | undefined)
}

export interface FeaturesWindowsOptions {
  /** Run each workspace as a macOS Desktop. On by default, off by default in embedded mode. */
  get desktops(): boolean
  set desktops(value: boolean | undefined)
  /** Group windows as tabs. On by default, off by default in embedded mode. */
  get tabGroups(): boolean
  set tabGroups(value: boolean | undefined)
  /** Lay out windows with the layouts. On by default, off by default in embedded mode. */
  get tiling(): boolean
  set tiling(value: boolean | undefined)
}

export interface FeaturesOptions {
  get input(): FeaturesInputOptions
  set input(value: Input<FeaturesInputOptions> | undefined)
  get presentation(): FeaturesPresentationOptions
  set presentation(value: Input<FeaturesPresentationOptions> | undefined)
  get services(): FeaturesServicesOptions
  set services(value: Input<FeaturesServicesOptions> | undefined)
  get windows(): FeaturesWindowsOptions
  set windows(value: Input<FeaturesWindowsOptions> | undefined)
}

export interface FloatingOptions {
  /** Bundle IDs of the apps that float. `com.adobe.*` matches every Adobe app. */
  get apps(): List<string>
  set apps(value: readonly string[] | undefined)
  /** Apps in the list. True: listed apps float. false: only listed apps are tiled. Default: `true`. */
  get listedAppsFloat(): boolean
  set listedAppsFloat(value: boolean | undefined)
  /** Float small windows. Dialogs and panels stay put. Default: `true`. */
  get smallWindows(): boolean
  set smallWindows(value: boolean | undefined)
}

export interface FocusOptions {
  /** Focus follows mouse. Hovering a window focuses it. Default: `true`. */
  get followsMouse(): boolean
  set followsMouse(value: boolean | undefined)
  /** Only in window mode. Hovering focuses a window only while window mode is on. Default: `true`. */
  get followsMouseInModeOnly(): boolean
  set followsMouseInModeOnly(value: boolean | undefined)
  /** Mouse follows focus. The pointer jumps to the window you focus. Default: `true`. */
  get mouseFollowsFocus(): boolean
  set mouseFollowsFocus(value: boolean | undefined)
}

export interface FocusDimOptions {
  /** Blur other windows. Softens everything but the focused window. Default: `false`. */
  get blur(): boolean
  set blur(value: boolean | undefined)
  /** Blur radius. How soft the other windows look. From 1 to 100. Default: `20`. */
  get blurRadius(): number
  set blurRadius(value: number | undefined)
  /** Dim other windows. Darkens everything but the focused window. Default: `false`. */
  get dim(): boolean
  set dim(value: boolean | undefined)
  /** Dim strength. How dark the other windows get. From 0 to 1. Default: `0.5`. */
  get dimStrength(): number
  set dimStrength(value: number | undefined)
}

export interface GapsOptions {
  /** Gaps between windows. Gaps between windows. Default: `true`. */
  get enabled(): boolean
  set enabled(value: boolean | undefined)
  /** Gap size. `gaps_in` is accepted and doubled. From 0 to 100. Default: `10`. */
  get size(): number
  set size(value: number | undefined)
  /** Smart gaps. No gaps when a window is alone. Default: `true`. */
  get smart(): boolean
  set smart(value: boolean | undefined)
}

export interface KeyboardHelpOptions {
  /** Show keyboard help. On-screen keyboard help in window mode. Default: `true`. */
  get enabled(): boolean
  set enabled(value: boolean | undefined)
  /** Keyboard finish. Used by keyboard help and Shortcut Map. Default: `auto`. */
  get finish(): "auto" | "macbook-pro" | "macbook-air" | "macbook-neo" | "magic-keyboard" | (string & {})
  set finish(value: "auto" | "macbook-pro" | "macbook-air" | "macbook-neo" | "magic-keyboard" | (string & {}) | undefined)
  /** Toggles the keyboard help in window mode. Default: `?`. */
  get key(): string
  set key(value: string | undefined)
}

export interface LabOptions {
  /** Resize animation. Color fills and snapshots keep slow apps smooth. Both need Screen Recording. Default: `live`. */
  get resizeAnimation(): "live" | "color-fill" | "snapshot"
  set resizeAnimation(value: "live" | "color-fill" | "snapshot" | undefined)
}

export interface LayoutHudOptions {
  /** Show layout name on change. A short card in the middle of the screen. Default: `false`. */
  get enabled(): boolean
  set enabled(value: boolean | undefined)
  /** Also when switching spaces. Default: `true`. */
  get onSpaceChange(): boolean
  set onSpaceChange(value: boolean | undefined)
}

export interface MotionOptions {
  /** Bounciness. How far springs swing, balls bounce and overshoot goes. From 0 to 1. Default: `0.5`. */
  get bounce(): number
  set bounce(value: number | undefined)
  /** Curve. How windows speed up and settle. Default: `ease-out`. */
  get curve(): "ease-out" | "ease-in-out" | "linear" | "spring" | "bounce" | "overshoot" | `cubic-bezier(${number}, ${number}, ${number}, ${number})`
  set curve(value: "ease-out" | "ease-in-out" | "linear" | "spring" | "bounce" | "overshoot" | `cubic-bezier(${number}, ${number}, ${number}, ${number})` | undefined)
  /** Duration. From 0 to 5. Default: `0.12`. */
  get duration(): number
  set duration(value: number | undefined)
  /** Animate windows. Windows glide to their new place. Default: `true`. */
  get enabled(): boolean
  set enabled(value: boolean | undefined)
  /** Window mode effect. Shown at the screen edges while window mode is on. Default: `draw`. */
  get modeEffect(): "draw" | "ripple" | "corners" | "none"
  set modeEffect(value: "draw" | "ripple" | "corners" | "none" | undefined)
  /** Panel animation. How Overview and keyboard help come and go. Default: `rise`. */
  get panels(): "rise" | "pop" | "focus" | "tile" | "draw"
  set panels(value: "rise" | "pop" | "focus" | "tile" | "draw" | undefined)
  /** Sets the duration, curve and bounce together, like the style tiles in Settings → Motion. A field you set after it overrides only that field. */
  get style(): MotionStyle | undefined
  set style(value: MotionStyle | undefined | undefined)
}

export interface MouseOptions {
  /** Drag window edges to resize the main pane. Resize a tiled window with the mouse, and the main pane follows. Default: `true`. */
  get resizesWindows(): boolean
  set resizesWindows(value: boolean | undefined)
  /** Split handle. Drag the bar between the sides to resize. Click it to swap the sides. Default: `true`. */
  get splitHandle(): boolean
  set splitHandle(value: boolean | undefined)
  /** Drag to swap. Drop a window on another to trade places. Default: `true`. */
  get swapsWindows(): boolean
  set swapsWindows(value: boolean | undefined)
}

export interface PaddingOptions {
  /** From 0 to 500. Default: `10`. */
  get bottom(): number
  set bottom(value: number | undefined)
  /** `screen-padding` or `gaps_out` sets all four sides. From 0 to 500. Default: `10`. */
  get left(): number
  set left(value: number | undefined)
  /** From 0 to 500. Default: `10`. */
  get right(): number
  set right(value: number | undefined)
  /** From 0 to 500. Default: `10`. */
  get top(): number
  set top(value: number | undefined)
}

export interface SwitcherOptions {
  /** Apps the switcher hides. Apps the window switcher never shows; wildcards like com.adobe.* work. Default: `[]`. */
  get exclude(): List<string>
  set exclude(value: readonly string[] | undefined)
  /** Instant jump. A search with one prefix match opens by itself. Default: `true`. */
  get instantJump(): boolean
  set instantJump(value: boolean | undefined)
  /** Jump delay. 0 opens the match at once. From 0 to 2000. Default: `300`. */
  get jumpDelay(): number
  set jumpDelay(value: number | undefined)
}

export interface TabsOptions {
  /** Auto-hide tab strip. Tab groups hide their tabs. Move the pointer to the window top to show them. Default: `false`. */
  get autoHideStrip(): boolean
  set autoHideStrip(value: boolean | undefined)
  /** Show notification badges on tabs. A tab shows the unread count of its app or window. Default: `true`. */
  get notificationBadges(): boolean
  set notificationBadges(value: boolean | undefined)
}

export interface WorkspacesOptions {
  /** True: workspaces live on the current Desktop and CatWM parks the windows of hidden workspaces in a screen corner (SkyRose). Wins over `workspaces.virtual`. Default: `false`. */
  get parked(): boolean
  set parked(value: boolean | undefined)
  /** Number workspaces on each display. Each display starts at workspace 1. Off: all displays share one set of numbers. Default: `true`. */
  get perDisplay(): boolean
  set perDisplay(value: boolean | undefined)
  /** Remove empty workspaces when you leave them. Removes the empty Desktop too. Default: `true`. */
  get removeEmpty(): boolean
  set removeEmpty(value: boolean | undefined)
  /** Suggest Overview for a crowded workspace. A tip under the menu bar icon, at most once a day. From 0 to 100. Default: `5`. */
  get sortNudge(): number
  set sortNudge(value: number | undefined)
  /** Stay on this workspace when closing a window. Default: `true`. */
  get stayAfterClose(): boolean
  set stayAfterClose(value: boolean | undefined)
  /** Control macOS Desktops with CatWM. CatWM controls workspace keys, animation and Overview. Default: `true`. */
  get virtual(): boolean
  set virtual(value: boolean | undefined)
}

export interface Options {
  /** Quick actions at the pointer. In window mode, tap the mode's modifier to save or open a workspace template. Default: `true`. */
  get cursorActions(): boolean
  set cursorActions(value: boolean | undefined)
  /** Verbose logging. Writes every step to the log. Default: `false`. */
  get debugLogging(): boolean
  set debugLogging(value: boolean | undefined)
  get features(): FeaturesOptions
  set features(value: Input<FeaturesOptions> | undefined)
  get floating(): FloatingOptions
  set floating(value: Input<FloatingOptions> | undefined)
  get focus(): FocusOptions
  set focus(value: Input<FocusOptions> | undefined)
  get focusDim(): FocusDimOptions
  set focusDim(value: Input<FocusDimOptions> | undefined)
  get gaps(): GapsOptions
  set gaps(value: Input<GapsOptions> | undefined)
  /** Ignore menu bar when tiling. Use this if you hide the menu bar. Default: `false`. */
  get ignoreMenuBar(): boolean
  set ignoreMenuBar(value: boolean | undefined)
  get keyboardHelp(): KeyboardHelpOptions
  set keyboardHelp(value: Input<KeyboardHelpOptions> | undefined)
  get lab(): LabOptions
  set lab(value: Input<LabOptions> | undefined)
  get layoutHud(): LayoutHudOptions
  set layoutHud(value: Input<LayoutHudOptions> | undefined)
  /** The layouts that `cyclelayout` steps through, each one once. */
  get layouts(): List<Layout>
  set layouts(value: readonly Layout[] | undefined)
  /** Your main modifier. Window mode and the pointer actions use it. The default is `alt`. */
  get mod(): Mod | readonly Mod[]
  set mod(value: Mod | readonly Mod[] | undefined)
  get motion(): MotionOptions
  set motion(value: Input<MotionOptions> | undefined)
  get mouse(): MouseOptions
  set mouse(value: Input<MouseOptions> | undefined)
  /** New windows become main. Default: `false`. */
  get newWindowsToMain(): boolean
  set newWindowsToMain(value: boolean | undefined)
  /** No padding on the built-in display. Default: `true`. */
  get noPaddingOnBuiltinDisplay(): boolean
  set noPaddingOnBuiltinDisplay(value: boolean | undefined)
  /** Space between the screen edges and the windows. A number sets all four sides. */
  get padding(): PaddingOptions
  set padding(value: number | Input<PaddingOptions> | undefined)
  /** Send performance reports. Repeated slow animations and hangs. Numbers and app IDs only. Default: `false`. */
  get perfReports(): boolean
  set perfReports(value: boolean | undefined)
  /** Main pane resize step. How much the split moves each time. Default: `5`. */
  get resizeStep(): number
  set resizeStep(value: number | undefined)
  get switcher(): SwitcherOptions
  set switcher(value: Input<SwitcherOptions> | undefined)
  get tabs(): TabsOptions
  set tabs(value: Input<TabsOptions> | undefined)
  /** Save tabs and folders. Browser tabs, terminal tabs, Finder folders and editor projects. macOS asks once for each app. Default: `false`. */
  get templateAppScripting(): boolean
  set templateAppScripting(value: boolean | undefined)
  get workspaces(): WorkspacesOptions & WorkspaceRuleCall
  set workspaces(value: Input<WorkspacesOptions> | undefined)
}

export interface ScopedFocusDimOptions {
  /** Blur other windows. Softens everything but the focused window. Default: `false`. */
  get blur(): boolean
  set blur(value: boolean | undefined)
  /** Blur radius. How soft the other windows look. From 1 to 100. Default: `20`. */
  get blurRadius(): number
  set blurRadius(value: number | undefined)
  /** Dim other windows. Darkens everything but the focused window. Default: `false`. */
  get dim(): boolean
  set dim(value: boolean | undefined)
  /** Dim strength. How dark the other windows get. From 0 to 1. Default: `0.5`. */
  get dimStrength(): number
  set dimStrength(value: number | undefined)
}

export interface ScopedGapsOptions {
  /** Gaps between windows. Gaps between windows. Default: `true`. */
  get enabled(): boolean
  set enabled(value: boolean | undefined)
  /** Gap size. `gaps_in` is accepted and doubled. From 0 to 100. Default: `10`. */
  get size(): number
  set size(value: number | undefined)
  /** Smart gaps. No gaps when a window is alone. Default: `true`. */
  get smart(): boolean
  set smart(value: boolean | undefined)
}

export interface ScopedMotionOptions {
  /** Bounciness. How far springs swing, balls bounce and overshoot goes. From 0 to 1. Default: `0.5`. */
  get bounce(): number
  set bounce(value: number | undefined)
  /** Curve. How windows speed up and settle. Default: `ease-out`. */
  get curve(): "ease-out" | "ease-in-out" | "linear" | "spring" | "bounce" | "overshoot" | `cubic-bezier(${number}, ${number}, ${number}, ${number})`
  set curve(value: "ease-out" | "ease-in-out" | "linear" | "spring" | "bounce" | "overshoot" | `cubic-bezier(${number}, ${number}, ${number}, ${number})` | undefined)
  /** Duration. From 0 to 5. Default: `0.12`. */
  get duration(): number
  set duration(value: number | undefined)
  /** Animate windows. Windows glide to their new place. Default: `true`. */
  get enabled(): boolean
  set enabled(value: boolean | undefined)
  /** Sets the duration, curve and bounce together, like the style tiles in Settings → Motion. A field you set after it overrides only that field. */
  get style(): MotionStyle | undefined
  set style(value: MotionStyle | undefined | undefined)
}

export interface ScopedPaddingOptions {
  /** From 0 to 500. Default: `10`. */
  get bottom(): number
  set bottom(value: number | undefined)
  /** `screen-padding` or `gaps_out` sets all four sides. From 0 to 500. Default: `10`. */
  get left(): number
  set left(value: number | undefined)
  /** From 0 to 500. Default: `10`. */
  get right(): number
  set right(value: number | undefined)
  /** From 0 to 500. Default: `10`. */
  get top(): number
  set top(value: number | undefined)
}

export interface ScopedOptions {
  get focusDim(): ScopedFocusDimOptions
  set focusDim(value: Input<ScopedFocusDimOptions> | undefined)
  get gaps(): ScopedGapsOptions
  set gaps(value: Input<ScopedGapsOptions> | undefined)
  /** The layouts that `cyclelayout` steps through, each one once. */
  get layouts(): List<Layout>
  set layouts(value: readonly Layout[] | undefined)
  get motion(): ScopedMotionOptions
  set motion(value: Input<ScopedMotionOptions> | undefined)
  /** New windows become main. Default: `false`. */
  get newWindowsToMain(): boolean
  set newWindowsToMain(value: boolean | undefined)
  /** Space between the screen edges and the windows. A number sets all four sides. */
  get padding(): ScopedPaddingOptions
  set padding(value: number | Input<ScopedPaddingOptions> | undefined)
}

/** A count of windows: an exact number, or a range. */
export type Count = number | { atLeast?: number; atMost?: number }

/** The display: its name, or the built-in or an external one. */
export type Display = "builtin" | "external" | (string & {})

/** Which windows a rule matches. Every field you give has to match. */
export interface WindowMatch {
  /** A bundle ID. `com.adobe.*` matches every Adobe app. */
  app?: string
  /** The exact title, or a regular expression. */
  title?: string | RegExp
  pid?: number
  workspace?: string
  display?: Display
  floating?: boolean
  minimized?: boolean
  fullscreen?: boolean
}

/** Which workspaces a rule matches. Every field you give has to match. */
export interface WorkspaceMatch {
  /** The number of windows on the workspace, tiled or floating. */
  windows?: Count
  /** The most windows any one app has on the workspace. */
  sameApp?: Count
  /** At least one window of this bundle ID. */
  app?: string
  layout?: Layout
  name?: string
  display?: Display
  /** The workspace with the focused window. */
  focused?: boolean
}

/** What a window rule can do to the window that starts matching. */
export interface WindowRule {
  float(): void
  tile(): void
  fullscreen(): void
  size: { width: number; height: number }
  position: "center" | { x: number; y: number }
  workspace: string
  display: Display
}

/** The focused window as it was when you pressed the key. Its methods run after your function ends. */
export interface WindowHandle {
  readonly title: string
  /** The bundle ID. */
  readonly app: string
  readonly pid: number
  readonly frame: { readonly x: number; readonly y: number; readonly width: number; readonly height: number }
  float(): void
  tile(): void
  fullscreen(): void
  resize(width: number, height: number): void
  move(x: number, y: number): void
  center(): void
  moveTo(workspace: string): void
}

/**
 * `catwm.workspaces(match, set)` runs `set` once, while the config loads. The options it sets apply to the
 * workspaces that match. Its `scoped` argument shows which options a workspace can have.
 * `catwm.workspaces` also holds the workspace options, such as `catwm.workspaces.virtual`.
 */
export type WorkspaceRuleCall = (match: WorkspaceMatch, set: (scoped: ScopedOptions) => void) => void

export interface Catwm extends Options {
  /**
   * Binds a key to an action, or to a function that runs when you press it. The function can only change
   * the focused window, through `catwm.window.focused`.
   */
  bind(
    mods: readonly Mod[],
    key: Key,
    run: Action | (() => void),
    options?: { repeat?: boolean; submap?: string }
  ): void
  /** Runs `set` once, while the config loads. It records what to do to each window that starts matching. */
  windows(match: WindowMatch, set: (win: WindowRule) => void): void
  readonly window: {
    /** The focused window. It works only inside a function you pass to `catwm.bind`. */
    readonly focused: WindowHandle
  }
}

export const catwm: Catwm
