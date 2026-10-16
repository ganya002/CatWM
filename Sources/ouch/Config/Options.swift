// Config: the table of scalar options. One entry per config key: where it lives in `Config`, how it reads and
// writes, and how Settings shows and finds it. The parser, the saved file, the default config, animation
// configs and the settings search all come from this table, so a new option is a `Config` property, one entry
// here, its Settings row and a line in Resources/AgentDocs/config.md (a test checks the docs).
import AppKit

enum OptionGroup {
    /// Saved with everything else.
    case general
    /// Part of an animation config: Configs swaps these as a set.
    case animation
}

/// How Settings shows an option and how the search finds it.
struct SettingInfo {
    let pane: Pane
    /// The row's anchor and search id, e.g. `windows.dimOthers`.
    let id: String
    let label: String
    var help: String? = nil
    var keywords = ""
    var advanced = false
    /// The slider's range, in its own units (the option's value × `scale`).
    var range: ClosedRange<Double>? = nil
    var scale: Double = 1
}

/// One scalar option of the config file.
struct ConfigOption {
    /// The name written to the file, e.g. `dim-strength`.
    let key: String
    /// Other names the parser accepts (Hyprland's, mostly). `-` and `_` are the same.
    var aliases: [String] = []
    var group = OptionGroup.general
    /// A `# ---- title ----` line (after a blank line) above this option: it starts a part of the file.
    var section: String? = nil
    /// Comment lines written just above the option.
    var note: String? = nil
    /// The values the parser keeps; it clamps others into this range.
    var valid: ClosedRange<Double>? = nil
    var setting: SettingInfo? = nil
    let path: PartialKeyPath<Config>
    /// Reads a value into the config. Returns an error message, or nil.
    let read: (inout Config, _ value: String, _ rawKey: String) -> String?
    let text: (Config) -> String
    let copy: (inout Config, Config) -> Void
    /// The default as a number, for the Settings reset button (0 for options that aren't numbers).
    let number: (Config) -> Double

    init<V>(_ key: String, _ path: WritableKeyPath<Config, V>, read: @escaping (String, _ rawKey: String) -> (V?, String?),
            text: @escaping (V) -> String, number: @escaping (V) -> Double = { _ in 0 }) {
        self.key = key
        self.path = path
        self.read = { c, v, raw in
            let (value, error) = read(v, raw)
            if let value { c[keyPath: path] = value }
            return error
        }
        self.text = { text($0[keyPath: path]) }
        self.copy = { $0[keyPath: path] = $1[keyPath: path] }
        self.number = { number($0[keyPath: path]) }
    }

    var names: [String] { [key] + aliases }
    var defaultText: String { text(Config()) }

    func aliases(_ a: String...) -> Self { var o = self; o.aliases = a; return o }
    func section(_ s: String) -> Self { var o = self; o.section = s; return o }
    func note(_ s: String) -> Self { var o = self; o.note = s; return o }
    func animation() -> Self { var o = self; o.group = .animation; return o }
    func setting(_ pane: Pane, _ id: String, _ label: String, help: String? = nil, keywords: String = "", advanced: Bool = false,
                 range: ClosedRange<Double>? = nil, scale: Double = 1) -> Self {
        var o = self
        o.setting = SettingInfo(pane: pane, id: id, label: label, help: help, keywords: keywords, advanced: advanced, range: range, scale: scale)
        return o
    }

    // MARK: Kinds

    static let trueWords = ["true", "yes", "on", "1"], falseWords = ["false", "no", "off", "0"]

    /// A typo such as `ture` is an error, and the option reads as false.
    static func readBool(_ v: String, _ rawKey: String) -> (Bool, String?) {
        let l = v.lowercased()
        return (trueWords.contains(l), trueWords.contains(l) || falseWords.contains(l) ? nil : "`\(rawKey)` needs true or false")
    }

    static func bool(_ key: String, _ path: WritableKeyPath<Config, Bool>) -> Self {
        Self(key, path, read: { v, raw in let (b, error) = readBool(v, raw); return (b, error) }, text: { $0 ? "true" : "false" })
    }

    /// A number. `convert` maps the written value (a percent, say) to the stored one, before the clamp to `valid`.
    static func number<V>(_ key: String, _ path: WritableKeyPath<Config, V>, valid: ClosedRange<Double>? = nil,
                          convert: @escaping (Double) -> Double = { $0 }, make: @escaping (Double) -> V,
                          text: @escaping (V) -> String, number: @escaping (V) -> Double) -> Self {
        var o = Self(key, path, read: { v, raw in
            // "nan" and "inf" parse as Doubles but poison every frame computed from them.
            guard let n = Double(v), n.isFinite else { return (nil, "`\(raw)` needs a number") }
            var x = convert(n)
            if let valid { x = min(valid.upperBound, max(valid.lowerBound, x)) }
            return (make(x), nil)
        }, text: text, number: number)
        o.valid = valid
        return o
    }

    static func points(_ key: String, _ path: WritableKeyPath<Config, CGFloat>, valid: ClosedRange<Double>? = nil,
                       convert: @escaping (Double) -> Double = { $0 }) -> Self {
        number(key, path, valid: valid, convert: convert, make: { CGFloat($0) }, text: { String(format: "%g", Double($0)) }, number: { Double($0) })
    }

    /// One of an enum's raw values, any case.
    static func choice<V: RawRepresentable & CaseIterable>(_ key: String, _ path: WritableKeyPath<Config, V>, noun: String) -> Self
    where V.RawValue == String {
        Self(key, path, read: { v, _ in
            guard let x = V(rawValue: v.lowercased()) else {
                return (nil, "unknown \(noun) `\(v)` (\(V.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            return (x, nil)
        }, text: { $0.rawValue })
    }

    // MARK: Lookup

    private static let byName: [String: ConfigOption] = {
        var d: [String: ConfigOption] = [:]
        for o in Options.all { for n in o.names { d[norm(n)] = o } }
        return d
    }()

    /// The option a key names (`Dim-Strength`, `dim_inactive`…), if it is in the table.
    static func named(_ key: String) -> ConfigOption? { byName[norm(key)] }

    /// The option stored at a `Config` key path. Settings rows use this; every row's option is in the table.
    static func at(_ path: PartialKeyPath<Config>) -> ConfigOption {
        guard let o = Options.all.first(where: { $0.path == path }) else { fatalError("no config option for \(path)") }
        return o
    }

    static func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "-", with: "_") }
}

// MARK: - The table

enum Options {
    /// In file order. `section` starts a part of the file; the animation group stays together.
    static let all: [ConfigOption] = [
        .bool("floating-is-blacklist", \.floatingIsBlacklist)
            .setting(.windows, "windows.floatingMode", "Apps in the list", keywords: "floating apps float exclude blacklist whitelist tile only"),

        // Gaps
        .bool("window-margins", \.windowMargins)
            .section("gaps")
            .note("Hyprland names also work: gaps_in = per-window gap, gaps_out = screen padding.")
            .setting(.layout, "layout.gaps", "Gaps between windows", keywords: "margin spacing"),
        .points("window-margin-size", \.windowMarginSize)
            .setting(.layout, "layout.gapSize", "Gap size", keywords: "margin spacing points", range: 0...60),
        .bool("smart-window-margins", \.smartWindowMargins).aliases("smart-gaps")
            .setting(.layout, "layout.smartGaps", "Smart gaps", help: "No gaps when a window is alone", keywords: "single window no gaps"),
        .points("screen-padding-left", \.paddingLeft),
        .points("screen-padding-right", \.paddingRight),
        .points("screen-padding-top", \.paddingTop),
        .points("screen-padding-bottom", \.paddingBottom),
        .bool("disable-padding-on-builtin-display", \.disablePaddingOnBuiltinDisplay)
            .setting(.layout, "layout.builtin", "No padding on the built-in display", keywords: "laptop macbook"),
        .bool("ignore-menu-bar", \.ignoreMenuBar)
            .setting(.layout, "layout.menuBar", "Ignore menu bar when tiling", help: "Use this if you hide the menu bar",
                     keywords: "tile over hidden menubar", advanced: true),

        // Behaviour
        .bool("mouse-follows-focus", \.mouseFollowsFocus).section("behaviour")
            .setting(.windows, "windows.mff", "Mouse follows focus", help: "The pointer jumps to the window you focus", keywords: "pointer cursor warp"),
        .bool("focus-follows-mouse", \.focusFollowsMouse).aliases("follow_mouse")
            .setting(.windows, "windows.ffm", "Focus follows mouse", help: "Hovering a window focuses it", keywords: "hover pointer"),
        .bool("focus-follows-mouse-in-mode-only", \.focusFollowsMouseInModeOnly)
            .note("With focus-follows-mouse on: hovering focuses a window only while window mode is on.")
            .setting(.windows, "windows.ffmModeOnly", "Only in window mode", help: "Hovering focuses a window only while window mode is on",
                     keywords: "focus follows mouse hover pointer submap"),
        .bool("mouse-swaps-windows", \.mouseSwapsWindows)
            .setting(.windows, "windows.dragSwap", "Drag to swap", help: "Drop a window on another to trade places", keywords: "mouse move"),
        .bool("mouse-resizes-windows", \.mouseResizesWindows)
            .setting(.windows, "windows.resizeMain", "Drag window edges to resize the main pane",
                     help: "Resize a tiled window with the mouse, and the main pane follows", keywords: "mouse ratio"),
        .bool("new-windows-to-main", \.newWindowsToMain).aliases("new_is_master")
            .setting(.windows, "windows.newMain", "New windows become main", keywords: "open", advanced: true),
        .bool("float-small-windows", \.floatSmallWindows)
            .setting(.windows, "windows.floatSmall", "Float small windows", help: "Dialogs and panels stay put", keywords: "dialogs panels", advanced: true),
        .number("window-resize-step", \.windowResizeStep, convert: { $0 >= 1 ? $0 / 100 : $0 }, make: { CGFloat($0) },
                // Below 1% the percent form would read back as a fraction, so write the fraction itself.
                text: { String(format: "%g", Double($0 >= 0.01 ? $0 * 100 : $0)) }, number: { Double($0) })
            .note("How far the main pane grows or shrinks each time, in percent (5) or as a fraction (0.05).")
            .setting(.layout, "layout.resizeStep", "Main pane resize step", help: "How much the split moves each time",
                     keywords: "ratio grow shrink percent", range: 1...25, scale: 100),
        .bool("enables-layout-hud", \.enablesLayoutHUD)
            .setting(.layout, "layout.hud", "Show layout name on change", help: "A short card in the middle of the screen", keywords: "hud overlay"),
        .bool("enables-layout-hud-on-space-change", \.enablesLayoutHUDOnSpaceChange)
            .setting(.layout, "layout.hudSpaces", "Also when switching spaces", keywords: "show layout name hud desktop", advanced: true),

        // The focused window
        .bool("dim-other-windows", \.dimOtherWindows).aliases("dim_inactive")
            .section("focused window")
            .note("Make the focused window stand out: darken the others (strength 0-1) and/or blur them (radius in points).")
            .setting(.windows, "windows.dimOthers", "Dim other windows", help: "Darkens everything but the focused window",
                     keywords: "focus darken inactive spotlight hazeover"),
        .points("dim-strength", \.dimStrength, valid: 0...1, convert: { $0 > 1 ? $0 / 100 : $0 })
            .setting(.windows, "windows.dimStrength", "Dim strength", help: "How dark the other windows get",
                     keywords: "darken amount opacity", range: 0...100, scale: 100),
        .bool("blur-other-windows", \.blurOtherWindows)
            .setting(.windows, "windows.blurOthers", "Blur other windows", help: "Softens everything but the focused window",
                     keywords: "focus soft inactive spotlight"),
        .points("blur-radius", \.blurRadius, valid: 1...100, convert: { $0.rounded() })
            .setting(.windows, "windows.blurRadius", "Blur radius", help: "How soft the other windows look", keywords: "soft amount points", range: 2...60),

        // Workspaces and Sort Windows
        .bool("virtual-workspaces", \.virtualWorkspaces)
            .section("workspaces")
            .note("Ouch's own workspaces (instant, per display) instead of macOS Spaces.")
            .setting(.windows, "windows.workspaces", "Use Ouch workspaces", help: "Instant, per-display workspaces instead of macOS Spaces",
                     keywords: "spaces desktops virtual"),
        .bool("stay-on-workspace-after-close", \.stayOnWorkspaceAfterClose)
            .setting(.windows, "windows.stay", "Stay on this workspace when closing a window", keywords: "close jump", advanced: true),
        .choice("sort-strategy", \.sortStrategy, noun: "sort strategy")
            .note("Sort Windows: the grouping it opens with (task, app, focus or none), and how many windows one\n"
                + "workspace holds before Ouch offers to sort them (0 turns the offer off).")
            .setting(.windows, "windows.sortStrategy", "Sort windows by", help: "How the Sort Windows panel groups them when it opens",
                     keywords: "group organize task app focus panel"),
        .number("sort-nudge", \.sortNudge, valid: 0...100, make: { Int($0) }, text: { "\($0)" }, number: { Double($0) })
            .setting(.windows, "windows.sortNudge", "Suggest sorting a crowded workspace", help: "A tip under the menu bar icon, at most once a day",
                     keywords: "tip packed many windows organize", range: 3...20),

        // Keyboard help
        .bool("keyboard-help", \.keyboardHelp)
            .section("keyboard help")
            .note("Keep holding the window-mode chord's modifier (or press keyboard-help-key in window mode) to see\n"
                + "every window-mode key on an on-screen keyboard.")
            .setting(.shortcuts, "shortcuts.keyboardHelp", "Show keyboard help", keywords: "on-screen hold command cmd caps lock question mark"),
        ConfigOption("keyboard-help-key", \Config.keyboardHelpKey, read: { v, _ -> (String?, String?) in
            guard v.count == 1 else { return (nil, "keyboard-help-key must be a single character, such as ?") }
            return (v, nil)
        }, text: { $0.replacingOccurrences(of: "#", with: "##") }),
        ConfigOption("keyboard-finish", \Config.keyboardFinish, read: { v, _ -> (String?, String?) in
            guard MacKeyboard.isValid(v) else {
                return (nil, "unknown keyboard finish `\(v)` (auto, macbook-pro, macbook-air, macbook-neo, magic-keyboard, or a finish like macbook-pro-space-black)")
            }
            return (MacKeyboard.slug(v), nil)
        }, text: { $0 })
            .note("The keyboard drawn there and in Settings: auto follows this Mac (model, colour, layout). Or pick a model\n"
                + "(macbook-pro, macbook-air, macbook-neo, magic-keyboard) or a finish, e.g. macbook-pro-space-black,\n"
                + "macbook-air-midnight, macbook-air-starlight, macbook-neo-citrus, imac-blue.")
            .setting(.shortcuts, "shortcuts.keyboardFinish", "Keyboard finish", help: "Used by keyboard help and Shortcut Map",
                     keywords: "keyboard model colour color auto macbook air pro neo magic"),
        .bool("cursor-actions", \.cursorActions)
            .note("In window mode a dot follows the pointer; tap the mode's modifier to open actions for the window under it.")
            .setting(.windows, "windows.cursorActions", "Quick actions at the pointer",
                     help: "In window mode, tap the mode's modifier. Press a shortcut below to run it",
                     keywords: "cursor mouse menu window mode tap modifier shortcut float zoom fullscreen minimize close"),

        // Animation (an animation config)
        .bool("animate", \.animate).aliases("animations").animation()
            .section("animation")
            .note("These also set how windows slide when you switch workspaces.")
            .setting(.motion, "motion.animate", "Animate windows", help: "Windows glide to their new place", keywords: "animation off motion"),
        .number("animation-duration", \.animationDuration, convert: { $0 > 5 ? $0 / 1000 : $0 }, make: { $0 },
                text: { String(format: "%g", ($0 * 1000).rounded() / 1000) }, number: { $0 }).animation()
            .note("Seconds; a value above 5 is read as milliseconds.")
            .setting(.motion, "motion.duration", "Duration", keywords: "speed time milliseconds animation", range: 0.05...1),
        ConfigOption("animation-curve", \Config.animationCurve, read: { v, _ -> (AnimationCurve?, String?) in
            guard let curve = AnimationCurve(v) else {
                return (nil, "unknown animation curve `\(v)` (ease-out, ease-in-out, linear, spring, bounce, overshoot or cubic-bezier(x1, y1, x2, y2))")
            }
            return (curve, nil)
        }, text: { $0.name }).animation()
            .note("ease-out, ease-in-out, linear, spring, bounce, overshoot or cubic-bezier(x1, y1, x2, y2)\n"
                + "like CSS (y past 0...1 overshoots).")
            .setting(.motion, "motion.curve", "Curve", help: "How windows speed up and settle",
                     keywords: "easing ease spring bounce overshoot linear", advanced: true),
        .number("animation-bounce", \.animationBounce, valid: 0...1, convert: { $0 > 1 ? $0 / 100 : $0 }, make: { $0 },
                text: { String(format: "%g", ($0 * 100).rounded() / 100) }, number: { $0 }).animation()
            .note("How lively spring, bounce and overshoot are, 0-1.")
            .setting(.motion, "motion.bounce", "Bounciness", help: "How far springs swing, balls bounce and overshoot goes",
                     keywords: "spring overshoot", advanced: true, range: 0...1),

        // Panels and window mode
        .choice("panel-animation", \.panelAnimation, noun: "panel animation")
            .section("panels and window mode")
            .note("How Sort Windows and keyboard help come and go: rise, pop, focus, tile or draw.")
            .setting(.motion, "motion.panels", "Panel animation", help: "How Sort Windows and keyboard help come and go",
                     keywords: "sort windows keyboard help rise pop focus tile draw open appear", advanced: true),
        .choice("mode-effect", \.modeEffect, noun: "mode effect")
            .note("The screen-edge effect while window mode is on: draw, ripple, corners or none.")
            .setting(.motion, "motion.modeEffect", "Window mode effect", help: "Shown at the screen edges while window mode is on",
                     keywords: "border edge draw ripple corners submap indicator", advanced: true),

        // Diagnostics
        .bool("debug-logging", \.debugLogging).section("diagnostics"),
        .bool("perf-reports", \.perfReports)
            .note("Send repeated animation slowdowns and hangs (numbers and app IDs only) to the developers."),
    ]

    /// Every option as config lines, with their comments: the layout cycle and floating list, then the table in
    /// order. The saved file and the default config both use these lines.
    static func lines(_ c: Config, includeAnimation: Bool = true) -> [String] {
        func heading(_ s: String) -> [String] {
            let head = "# ---- \(s) "
            return ["", head + String(repeating: "-", count: max(3, 78 - head.count))]
        }
        var out = Array(heading("layouts").dropFirst()) + [
            "# tall, tall-right, wide, middle-wide, fullscreen, column, row, floating, bsp, 3column-left,",
            "# 3column-middle, 3column-right, two-pane, two-pane-right, widescreen-tall, widescreen-tall-right",
            "layouts = " + c.layouts.map(\.rawValue).joined(separator: ", "),
        ]
        out += heading("floating apps") + [
            "# Bundle IDs to float (wildcards like com.adobe.* work). Set floating-is-blacklist = false",
            "# to make this a list of the ONLY apps that get tiled.",
            "floating = " + c.floating.joined(separator: ", "),
        ]
        for o in all where includeAnimation || o.group != .animation {
            if let s = o.section { out += heading(s) }
            if let note = o.note { out += note.components(separatedBy: "\n").map { "# " + $0 } }
            out.append("\(o.key) = \(o.text(c))")
        }
        return out
    }
}
