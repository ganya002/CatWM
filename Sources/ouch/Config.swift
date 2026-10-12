import AppKit

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

/// Amethyst's options, written in a Hyprland-style config file.
struct Config {
    var layouts: [Layout] = [.tall, .wide, .fullscreen, .bsp, .column]
    var windowMargins = true
    var windowMarginSize: CGFloat = 10
    var smartWindowMargins = false
    var paddingLeft: CGFloat = 10, paddingRight: CGFloat = 10, paddingTop: CGFloat = 10, paddingBottom: CGFloat = 10
    var mouseFollowsFocus = false
    var focusFollowsMouse = false
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
    var debugLogging = false
    /// Ouch's own workspaces (instant, per monitor, like Hyprland) instead of macOS Spaces.
    var virtualWorkspaces = true
    /// Closing a window keeps you on the current workspace instead of jumping to wherever macOS refocuses.
    var stayOnWorkspaceAfterClose = true
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

    static func parse(_ text: String) -> Config {
        var c = Config()
        var vars: [(String, String)] = []
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

    mutating func apply(_ rawKey: String, _ v: String) -> String? {
        var key = rawKey.lowercased().replacingOccurrences(of: "-", with: "_")
        let fullKey = key
        if let colon = key.lastIndex(of: ":") { key = String(key[key.index(after: colon)...]) } // general:gaps_in
        let num = Double(v).map { CGFloat($0) }
        let bool = ["true", "yes", "on", "1"].contains(v.lowercased())
        func needNum(_ set: (CGFloat) -> Void) -> String? {
            guard let num else { return "`\(rawKey)` needs a number" }
            set(num); return nil
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
        case "window_margins": windowMargins = bool
        case "window_margin_size": return needNum { windowMarginSize = $0 }
        case "gaps_in": return needNum { windowMarginSize = $0 * 2 } // Hyprland: per-window inner gap
        case "smart_window_margins", "smart_gaps": smartWindowMargins = bool
        case "screen_padding_left": return needNum { paddingLeft = $0 }
        case "screen_padding_right": return needNum { paddingRight = $0 }
        case "screen_padding_top": return needNum { paddingTop = $0 }
        case "screen_padding_bottom": return needNum { paddingBottom = $0 }
        case "screen_padding", "gaps_out":
            return needNum { paddingLeft = $0; paddingRight = $0; paddingTop = $0; paddingBottom = $0 }
        case "mouse_follows_focus": mouseFollowsFocus = bool
        case "focus_follows_mouse", "follow_mouse": focusFollowsMouse = bool
        case "mouse_swaps_windows": mouseSwapsWindows = bool
        case "mouse_resizes_windows": mouseResizesWindows = bool
        case "floating":
            var ids: [String] = []
            for id in v.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !id.isEmpty && !ids.contains(id) {
                ids.append(id)
            }
            floating = ids
        case "floating_is_blacklist": floatingIsBlacklist = bool
        case "float_small_windows": floatSmallWindows = bool
        case "new_windows_to_main", "new_is_master": newWindowsToMain = bool
        case "enables_layout_hud": enablesLayoutHUD = bool
        case "enables_layout_hud_on_space_change": enablesLayoutHUDOnSpaceChange = bool
        case "ignore_menu_bar": ignoreMenuBar = bool
        case "disable_padding_on_builtin_display": disablePaddingOnBuiltinDisplay = bool
        case "window_resize_step": return needNum { windowResizeStep = $0 >= 1 ? $0 / 100 : $0 }
        case "animate", "animations": animate = bool
        case "enabled": // only `animations { enabled }` is ours; `blur { enabled }` etc. are other blocks' options
            guard fullKey == "animations:enabled" else { return "unknown option `\(rawKey)`" }
            animate = bool
        case "animation_duration": return needNum { animationDuration = Double($0) > 5 ? Double($0) / 1000 : Double($0) }
        case "debug_logging": debugLogging = bool
        case "virtual_workspaces": virtualWorkspaces = bool
        case "stay_on_workspace_after_close": stayOnWorkspaceAfterClose = bool
        default: return "unknown option `\(rawKey)`"
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
        let seq = na <= nb ? Array(na...nb) : Array((nb...na).reversed())
        guard seq.count <= 100 else { return nil }
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

let defaultText = """
# Ouch config: Amethyst's options with Hyprland-style syntax.
# Edit, then reload from the menu bar or with $mod SHIFT, R.

# SUPER = Command, ALT = Option. Option is the default so app shortcuts (Cmd-Q, Cmd-C...) keep working.
$mod = ALT

# ---- layouts --------------------------------------------------------------
# tall, tall-right, wide, middle-wide, fullscreen, column, row, floating, bsp,
# 3column-left, 3column-middle, 3column-right, two-pane, two-pane-right,
# widescreen-tall, widescreen-tall-right
layouts = tall, wide, fullscreen, bsp, column

# ---- gaps (Hyprland names also work: gaps_in = per-window gap, gaps_out = screen padding)
window-margins = true
window-margin-size = 10
smart-window-margins = false
screen-padding-left = 10
screen-padding-right = 10
screen-padding-top = 10
screen-padding-bottom = 10
disable-padding-on-builtin-display = false
ignore-menu-bar = false

# ---- behaviour -------------------------------------------------------------
mouse-follows-focus = false
focus-follows-mouse = false
mouse-swaps-windows = true
mouse-resizes-windows = true
new-windows-to-main = false
float-small-windows = true
window-resize-step = 5
enables-layout-hud = true
enables-layout-hud-on-space-change = true

# Bundle IDs to float (wildcards like com.adobe.* work). Set floating-is-blacklist = false
# to make this a list of the ONLY apps that get tiled.
floating = com.apple.systempreferences, com.apple.SystemSettings, com.apple.calculator
floating-is-blacklist = true

# ---- animation -------------------------------------------------------------
animate = true
animation-duration = 0.18

# ---- keybinds: bind = MODS, key, dispatcher, args -------------------------
# Global binds work everywhere. Everything else lives in "window mode" (a Hyprland submap):
# press Cmd+Caps Lock, then single keys, vim style. Esc / i / Return or a mouse click leaves it.
bind = $mod, 1..0, workspace, 1..10
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
bind = , v, togglefloating
bind = , z, retile
bind = SHIFT, t, toggletiling
bind = SHIFT, r, reload
bind = , escape|i|return, submap, reset
bind = SUPER, capslock, submap, reset
submap = reset
"""
