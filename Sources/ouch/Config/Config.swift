// Config: the config model (options, key binds) and the parser for the Hyprland-style config file.
import AppKit

// MARK: - Key binds

struct KeyBinding {
    let keyCode: UInt16
    let mods: CGEventFlags
    let dispatcher: String
    let arg: String
    var submap = "" // "" = global; otherwise only active inside that submap (mode)
    var repeats = false // binde/bindel/bindle fire on key autorepeat
}

/// Hyprland comments: a single `#` starts one, `##` is a literal `#`.
func stripComment(_ line: String) -> String {
    var out = ""
    var it = line.makeIterator()
    while let ch = it.next() {
        if ch == "#" {
            var peek = it
            guard peek.next() == "#" else { break }
            it = peek
        }
        out.append(ch)
    }
    return out
}

// MARK: - Config

/// Amethyst's options, written in a Hyprland-style config file.
struct Config {
    var layouts: [Layout] = [.tall, .wide, .fullscreen, .bsp, .column]
    var windowMargins = true
    var windowMarginSize: CGFloat = 10
    var smartWindowMargins = false
    var paddingLeft: CGFloat = 10, paddingRight: CGFloat = 10, paddingTop: CGFloat = 10, paddingBottom: CGFloat = 10
    var mouseFollowsFocus = false
    var focusFollowsMouse = false
    /// Focus follows mouse only while window mode (or another submap) is on.
    var focusFollowsMouseInModeOnly = false
    var mouseSwapsWindows = true
    var mouseResizesWindows = true
    var floating: [String] = []
    var floatingIsBlacklist = true
    var floatSmallWindows = true
    var newWindowsToMain = false
    var enablesLayoutHUD = true
    var enablesLayoutHUDOnSpaceChange = true
    var ignoreMenuBar = false
    var disablePaddingOnBuiltinDisplay = false
    var windowResizeStep: CGFloat = 0.05
    var animate = true
    var animationDuration: Double = 0.18
    var animationCurve: AnimationCurve = .easeOut
    /// How lively spring, bounce and overshoot curves are, 0...1.
    var animationBounce: Double = 0.5
    var debugLogging = false
    /// Sends repeated animation slowdowns and hangs (numbers and app IDs only) to the developers' issue tracker.
    var perfReports = false
    /// Ouch's own workspaces (instant, per monitor, like Hyprland) instead of macOS Spaces.
    var virtualWorkspaces = true
    /// Closing a window keeps you on the current workspace instead of jumping to wherever macOS refocuses.
    var stayOnWorkspaceAfterClose = true
    /// Windows on one workspace before Ouch offers to sort them; 0 turns the offer off.
    var sortNudge = 5
    /// The grouping the Sort panel opens with.
    var sortStrategy: SortStrategy = .task
    /// Screen-edge effect while a mode is on: draw, ripple, corners or none.
    var modeEffect: ModeFX.Style = .draw
    /// Darken every window but the focused one, by `dimStrength` (0...1).
    var dimOtherWindows = false
    var dimStrength: CGFloat = 0.3
    /// Blur every window but the focused one, `blurRadius` points.
    var blurOtherWindows = false
    var blurRadius: CGFloat = 20
    var panelAnimation: PanelMotion = .rise
    /// The on-screen keyboard help: hold the mode chord, or press ? in a mode.
    var keyboardHelp = true
    /// The character that toggles the keyboard help inside a mode.
    var keyboardHelpKey = "?"
    /// In window mode, a dot beside the pointer; tapping the mode's modifier opens quick actions for the
    /// window under it.
    var cursorActions = true
    /// The main modifier (`$mod`, or Hyprland's `$mainMod`), resolved. A tap of it in a mode opens the quick actions.
    var mainMod: CGEventFlags = .maskAlternate
    /// The keyboard drawn in the Shortcut Map and the keyboard help: `auto` (this Mac), a finish such as
    /// `macbook-air-midnight`, or a family (`macbook-pro`, `macbook-air`, `macbook-neo`, `magic-keyboard`).
    var keyboardFinish = "auto"
    var bindings: [KeyBinding] = []
    var currentSubmap = "" // parser state while reading submap blocks
    var errors: [String] = []

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ouch/ouch.conf")
    private static let legacyURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/hyprthyst/hyprthyst.conf")

    static func load() -> Config {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The app used to be called Hyprthyst; carry its config over on first launch.
            if fm.fileExists(atPath: legacyURL.path) {
                try? fm.copyItem(at: legacyURL, to: url)
            } else {
                try? defaultText.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        let c = parse((try? String(contentsOf: url, encoding: .utf8)) ?? defaultText)
        c.errors.forEach { NSLog("Ouch config: %@", $0) }
        return c
    }

    /// Sets one option in the config file where it stands (or adds it above the binds), leaving the
    /// rest of the file, comments included, as written.
    static func write(option key: String, _ value: String) {
        let read = try? String(contentsOf: url, encoding: .utf8)
        guard read != nil || !FileManager.default.fileExists(atPath: url.path) else { return } // never replace a file we can't read
        let text = read ?? defaultText
        var lines = text.components(separatedBy: "\n")
        func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "-", with: "_") }
        let existing = lines.firstIndex { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { return false }
            return norm(t[..<eq].trimmingCharacters(in: .whitespaces)) == norm(key)
        }
        if let existing {
            lines[existing] = "\(key) = \(value)"
        } else {
            lines.insert("\(key) = \(value)", at: lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("bind") } ?? lines.count)
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> Config {
        var c = Config()
        var vars: [(String, String)] = []
        var modVar: String? // the first variable named like a modifier, as Settings reads it
        var blocks: [String] = [] // enclosing Hyprland category blocks, outermost first
        for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
            var line = stripComment(raw)
            line = line.trimmingCharacters(in: .whitespaces)
            // Hyprland category blocks (`general { ... }`) are accepted; keys inside get the block path as prefix.
            if line.hasSuffix("{") { blocks.append(String(line.dropLast()).trimmingCharacters(in: .whitespaces)); continue }
            if line == "}" { _ = blocks.popLast(); continue }
            if line.isEmpty { continue }
            guard let eq = line.firstIndex(of: "=") else { c.errors.append("line \(n + 1): expected `key = value`"); continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            for (k, v) in vars { value = value.replacingOccurrences(of: k, with: v) }
            if key.hasPrefix("$") {
                vars.removeAll { $0.0 == key }
                vars.append((key, value))
                vars.sort { $0.0.count > $1.0.count } // so $mod2 isn't eaten by $mod
                if key.lowercased().contains("mod"), (modVar ?? key) == key, let f = ConfigDocument.flags(value) {
                    modVar = key
                    c.mainMod = CGEventFlags(rawValue: UInt64(f.rawValue))
                }
                continue
            }
            // Hyprland submaps: binds after `submap = name` only work in that mode, until `submap = reset`.
            if key.lowercased() == "submap" {
                c.currentSubmap = value.lowercased() == "reset" ? "" : value
                continue
            }
            if let err = c.apply((blocks + [key]).joined(separator: ":"), value) { c.errors.append("line \(n + 1): \(err)") }
        }
        return c
    }

    /// Sets one option. Scalar options come from `Options.all`; only lists, binds and shorthands that set
    /// several options are read here.
    mutating func apply(_ rawKey: String, _ v: String) -> String? {
        var key = rawKey.lowercased().replacingOccurrences(of: "-", with: "_")
        let fullKey = key
        if let colon = key.lastIndex(of: ":") { key = String(key[key.index(after: colon)...]) } // general:gaps_in
        func needNum(_ set: (CGFloat) -> Void) -> String? {
            // "nan" and "inf" parse as Doubles but poison every frame computed from them
            guard let num = Double(v), num.isFinite else { return "`\(rawKey)` needs a number" }
            set(CGFloat(num)); return nil
        }

        switch key {
        case "bind", "binde", "bindr", "bindl", "bindel", "bindle": return parseBind(v, repeats: ["binde", "bindel", "bindle"].contains(key))
        case "bindm": return nil // mouse binds: dragging already moves/resizes tiles
        case "layouts":
            var list: [Layout] = []
            for name in v.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
                guard let l = Layout(rawValue: name) else { return "unknown layout `\(name)`" }
                if !list.contains(l) { list.append(l) } // a layout appears once in the cycle
            }
            if !list.isEmpty { layouts = list }
        case "floating":
            var ids: [String] = []
            for id in v.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !id.isEmpty && !ids.contains(id) {
                ids.append(id)
            }
            floating = ids
        case "gaps_in": return needNum { windowMarginSize = $0 * 2 } // Hyprland: per-window inner gap
        case "screen_padding", "gaps_out":
            return needNum { paddingLeft = $0; paddingRight = $0; paddingTop = $0; paddingBottom = $0 }
        case "enabled": // only `animations { enabled }` is ours; `blur { enabled }` etc. are other blocks' options
            guard fullKey == "animations:enabled" else { return "unknown option `\(rawKey)`" }
            let (on, error) = ConfigOption.readBool(v, rawKey)
            animate = on
            return error
        default:
            guard let option = ConfigOption.named(key) else { return "unknown option `\(rawKey)`" }
            return option.read(&self, v, rawKey)
        }
        return nil
    }

    private mutating func parseBind(_ v: String, repeats: Bool) -> String? {
        let parts = v.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return "bind needs `MODS, key, dispatcher[, args]`" }
        var mods: CGEventFlags = []
        for m in parts[0].uppercased().split(whereSeparator: { " _+".contains($0) }) {
            switch m {
            case "SUPER", "CMD", "COMMAND", "WIN", "META", "MOD4": mods.insert(.maskCommand)
            case "ALT", "OPT", "OPTION", "MOD1": mods.insert(.maskAlternate)
            case "CTRL", "CONTROL": mods.insert(.maskControl)
            case "SHIFT": mods.insert(.maskShift)
            default: return "unknown modifier `\(m)`"
            }
        }
        let dispatcher = parts[2].lowercased()
        let pairs: [(key: String, arg: String)]
        switch BindRange.pairs(key: parts[1], dispatcher: dispatcher, arg: parts.count > 3 ? parts[3] : "") {
        case .success(let p): pairs = p
        case .failure(let e): return e.message
        }
        for (key, arg) in pairs {
            guard let code = keyCodes[key.lowercased()] else { return "unknown key `\(key)`" }
            bindings.append(KeyBinding(keyCode: code, mods: mods, dispatcher: dispatcher, arg: arg, submap: currentSubmap, repeats: repeats))
        }
        return nil
    }
}

// MARK: - Bind ranges and special keys

/// Range binds, so one line can cover a run of keys:
///   bind = $mod, 1..0, workspace, 1..10      keys follow the number row, so 1..0 is ten keys
///   bind = $mod, a..d, ...    f1..f12    h|j|k|l with l|d|u|r
/// The arguments are expanded the same way and paired up with the keys; a single argument is
/// used for every key. `exec` arguments and anything containing spaces are never expanded.
enum BindRange {
    struct Failure: Error { let message: String }

    static let numberRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    static func isRange(_ s: String) -> Bool { s.contains("..") || s.contains("|") }

    static func expand(_ raw: String, keys: Bool) -> [String]? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.contains("|") {
            let parts = t.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.contains(where: \.isEmpty) ? nil : parts
        }
        guard let r = t.range(of: "..") else { return [t] }
        let a = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        var b = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
        while b.hasPrefix(".") { b.removeFirst() } // accept Kotlin-ish "1...5" too
        guard !a.isEmpty, !b.isEmpty else { return nil }

        if keys, let i = numberRow.firstIndex(of: a), let j = numberRow.firstIndex(of: b), i <= j {
            return Array(numberRow[i...j])
        }
        if a.count == 1, b.count == 1, let x = a.lowercased().unicodeScalars.first, let y = b.lowercased().unicodeScalars.first,
           ("a"..."z").contains(Character(x)), ("a"..."z").contains(Character(y)) {
            let seq = x.value <= y.value ? Array(x.value...y.value) : Array((y.value...x.value).reversed())
            let upper = a == a.uppercased()
            return seq.map { String(Character(UnicodeScalar($0)!)) }.map { upper ? $0.uppercased() : $0 }
        }
        // Shared prefix + number: 1..10, f1..f12, mon:0..mon:2 (or mon:0..2)
        func split(_ s: String) -> (prefix: String, n: Int)? {
            let digits = s.reversed().prefix { $0.isNumber }
            guard !digits.isEmpty, let n = Int(String(digits.reversed())) else { return nil }
            var prefix = String(s.dropLast(digits.count))
            if prefix.hasSuffix("-"), prefix.count == 1 { return (String(prefix.dropLast()), -n) }
            if prefix == "+" { prefix = "" }
            return (prefix, n)
        }
        guard let (pa, na) = split(a), let (pb, nb) = split(b), pb.isEmpty || pa.lowercased() == pb.lowercased() else { return nil }
        let (span, overflow) = nb.subtractingReportingOverflow(na)
        guard !overflow, span.magnitude < 100 else { return nil } // before building the array: 1..99999999999 would not fit
        let seq = na <= nb ? Array(na...nb) : Array((nb...na).reversed())
        return seq.map { pa + String($0) }
    }

    static func pairs(key: String, dispatcher: String, arg: String) -> Result<[(key: String, arg: String)], Failure> {
        guard let keys = expand(key, keys: true) else { return .failure(Failure(message: "can't read the key range `\(key)`")) }
        var args = [arg]
        if dispatcher != "exec", !arg.contains(" "), isRange(arg) {
            guard let a = expand(arg, keys: false) else { return .failure(Failure(message: "can't read the range `\(arg)`")) }
            args = a
        }
        if args.count == 1 { return .success(keys.map { ($0, args[0]) }) }
        guard args.count == keys.count else {
            return .failure(Failure(message: "\(keys.count) key\(keys.count == 1 ? "" : "s") but \(args.count) values"))
        }
        return .success(Array(zip(keys, args)).map { ($0, $1) })
    }
}

/// Pseudo key codes for scroll wheel and trackpad swipe binds. Real virtual key codes stop below 0x100.
enum SpecialKey {
    static let mouseUp: UInt16 = 0x1000, mouseDown: UInt16 = 0x1001, mouseLeft: UInt16 = 0x1002, mouseRight: UInt16 = 0x1003
    static let swipeLeft: UInt16 = 0x1010, swipeRight: UInt16 = 0x1011, swipeUp: UInt16 = 0x1012, swipeDown: UInt16 = 0x1013
    static func isScroll(_ code: UInt16) -> Bool { (0x1000...0x1003).contains(code) }
    static func isSwipe(_ code: UInt16) -> Bool { (0x1010...0x1013).contains(code) }
}

/// ANSI virtual key codes, named like xkb keysyms (what Hyprland uses) plus a few aliases.
let keyCodes: [String: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "equal": 24, "=": 24, "9": 25, "7": 26, "minus": 27, "-": 27, "8": 28, "0": 29,
    "bracketright": 30, "]": 30, "o": 31, "u": 32, "bracketleft": 33, "[": 33, "i": 34, "p": 35,
    "return": 36, "enter": 36, "l": 37, "j": 38, "apostrophe": 39, "quote": 39, "'": 39, "k": 40,
    "semicolon": 41, ";": 41, "backslash": 42, "\\": 42, "comma": 43, "n": 45, "m": 46,
    "slash": 44, "/": 44, "period": 47, ".": 47, "tab": 48, "space": 49, "grave": 50, "`": 50,
    "backspace": 51, "escape": 53, "esc": 53, "capslock": 57, "caps": 57, "caps_lock": 57,
    // ISO and JIS extras.
    "section": 10, "yen": 93, "underscore_jis": 94, "eisu": 102, "kana": 104,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
    "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    "home": 115, "pageup": 116, "prior": 116, "delete": 117, "end": 119, "pagedown": 121, "next": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,
    // Scroll wheel (Hyprland's names) and trackpad swipes.
    "mouse_up": SpecialKey.mouseUp, "mouse_down": SpecialKey.mouseDown,
    "mouse_left": SpecialKey.mouseLeft, "mouse_right": SpecialKey.mouseRight,
    "swipe_left": SpecialKey.swipeLeft, "swipe_right": SpecialKey.swipeRight,
    "swipe_up": SpecialKey.swipeUp, "swipe_down": SpecialKey.swipeDown,
]

/// The config a first run writes: every option at its default (from `Options`), a few apps that float, and the binds.
let defaultText: String = {
    var c = Config()
    c.floating = ["com.apple.systempreferences", "com.apple.SystemSettings", "com.apple.calculator"]
    return """
# Ouch config: Amethyst's options with Hyprland-style syntax.
# Edit, then reload from the menu bar or with $mod SHIFT, R.

# SUPER = Command, ALT = Option. Option is the default so app shortcuts (Cmd-Q, Cmd-C...) keep working.
$mod = ALT


""" + Options.lines(c).joined(separator: "\n") + "\n\n" + defaultBinds
}()

private let defaultBinds = """
# ---- keybinds: bind = MODS, key, dispatcher, args -------------------------
# Global binds work everywhere. Everything else lives in "window mode" (a Hyprland submap):
# press Cmd+Caps Lock, then single keys, vim style. Esc / i / Return or a mouse click leaves it.
bind = $mod, 1..0, workspace, 1..10
bind = $mod, o, sort
bind = SUPER, capslock, submap, window
# Scroll wheel / trackpad scroll while holding the modifier, and trackpad swipes:
# bind = $mod, mouse_down, workspace, e+1
# bind = $mod, mouse_up, workspace, e-1
# bind = $mod CTRL, swipe_left, workspace, e+1

submap = window
bind = , h|j|k|l, movefocus, l|d|u|r
bind = , left|down|up|right, movefocus, l|d|u|r
bind = SHIFT, h|j|k|l, movewindow, l|d|u|r
bind = SHIFT, left|down|up|right, movewindow, l|d|u|r
bind = , 1..0, workspace, 1..10
bind = SHIFT, 1..0, movetoworkspace, 1..10
bind = , w, focusmonitor, +1
bind = , b, focusmonitor, -1
bind = SHIFT, w, movewindow, mon:+1
bind = SHIFT, b, movewindow, mon:-1
bind = , n, cyclelayout, next
bind = , p, cyclelayout, prev
bind = , comma, splitratio, -0.05
bind = , period, splitratio, +0.05
bind = SHIFT, comma, layoutmsg, addmaster
bind = SHIFT, period, layoutmsg, removemaster
bind = , m, layoutmsg, swapwithmaster
bind = , tab, cyclenext
bind = SHIFT, tab, cyclenext, prev
bind = , f, fullscreen
bind = SHIFT, f, nativefullscreen
bind = , v, togglefloating
bind = , z, retile
bind = SHIFT, t, toggletiling
bind = SHIFT, r, reload
bind = , escape|i|return, submap, reset
bind = SUPER, capslock, submap, reset
submap = reset
"""


/// The gaming shortcut set: the same global binds, with window mode on WASD (Q/E for workspaces).
let wasdText: String = {
    let head = defaultText.components(separatedBy: "submap = window").first ?? defaultText
    return head + """
submap = window
bind = , w|a|s|d, movefocus, u|l|d|r
bind = , left|down|up|right, movefocus, l|d|u|r
bind = SHIFT, w|a|s|d, movewindow, u|l|d|r
bind = SHIFT, left|down|up|right, movewindow, l|d|u|r
bind = , q|e, workspace, e-1|e+1
bind = SHIFT, q|e, movetoworkspace, e-1|e+1
bind = , 1..0, workspace, 1..10
bind = SHIFT, 1..0, movetoworkspace, 1..10
bind = , r, cyclelayout, next
bind = SHIFT, r, cyclelayout, prev
bind = , f, fullscreen
bind = SHIFT, f, nativefullscreen
bind = , c, togglefloating
bind = , g, layoutmsg, swapwithmaster
bind = , space, focusmonitor, +1
bind = SHIFT, space, movewindow, mon:+1
bind = , comma, splitratio, -0.05
bind = , period, splitratio, +0.05
bind = SHIFT, comma, layoutmsg, addmaster
bind = SHIFT, period, layoutmsg, removemaster
bind = , tab, cyclenext
bind = SHIFT, tab, cyclenext, prev
bind = , z, retile
bind = SHIFT, t, toggletiling
bind = CTRL, r, reload
bind = , escape|return, submap, reset
bind = SUPER, capslock, submap, reset
submap = reset

"""
}()
