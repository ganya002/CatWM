import AppKit

struct Config {
    var layouts: [Layout] = [.tall, .wide, .fullscreen, .bsp, .column]
    var windowMargins = true
    var windowMarginSize: CGFloat = 10
    var smartWindowMargins = false
    var paddingLeft: CGFloat = 10, paddingRight: CGFloat = 10, paddingTop: CGFloat = 10, paddingBottom: CGFloat = 10
    var mouseFollowsFocus = false
    var focusFollowsMouse = false
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
    var animationBounce: Double = 0.5
    var debugLogging = false
    var perfReports = false
    var virtualWorkspaces = true
    var stayOnWorkspaceAfterClose = true
    var sortNudge = 5
    var sortStrategy: SortStrategy = .task
    var modeEffect: ModeFX.Style = .draw
    var dimOtherWindows = false
    var dimStrength: CGFloat = 0.3
    var blurOtherWindows = false
    var blurRadius: CGFloat = 20
    var panelAnimation: PanelMotion = .rise
    var keyboardHelp = true
    var keyboardHelpKey = "?"
    var cursorActions = true
    var mainMod: CGEventFlags = .maskAlternate
    var keyboardFinish = "auto"
    var bindings: [KeyBinding] = []
    var currentSubmap = ""
    var errors: [String] = []

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ouch/ouch.conf")
    private static let legacyURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/hyprthyst/hyprthyst.conf")

    static func load() -> Config {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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

    static func write(option key: String, _ value: String) {
        let read = try? String(contentsOf: url, encoding: .utf8)
        guard read != nil || !FileManager.default.fileExists(atPath: url.path) else { return }
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

    static func parse(_ text: String) -> Config {
        var c = Config()
        var vars: [(String, String)] = []
        var modVar: String?
        var blocks: [String] = []
        for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
            var line = stripComment(raw)
            line = line.trimmingCharacters(in: .whitespaces)
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
                vars.sort { $0.0.count > $1.0.count }
                if key.lowercased().contains("mod"), (modVar ?? key) == key, let f = ConfigDocument.flags(value) {
                    modVar = key
                    c.mainMod = CGEventFlags(rawValue: UInt64(f.rawValue))
                }
                continue
            }
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
        if let colon = key.lastIndex(of: ":") { key = String(key[key.index(after: colon)...]) }
        func needNum(_ set: (CGFloat) -> Void) -> String? {
            guard let num = Double(v), num.isFinite else { return "`\(rawKey)` needs a number" }
            set(CGFloat(num)); return nil
        }

        switch key {
        case "bind", "binde", "bindr", "bindl", "bindel", "bindle": return parseBind(v, repeats: ["binde", "bindel", "bindle"].contains(key))
        case "bindm": return nil
        case "layouts":
            var list: [Layout] = []
            for name in v.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
                guard let l = Layout(rawValue: name) else { return "unknown layout `\(name)`" }
                if !list.contains(l) { list.append(l) }
            }
            if !list.isEmpty { layouts = list }
        case "floating":
            var ids: [String] = []
            for id in v.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !id.isEmpty && !ids.contains(id) {
                ids.append(id)
            }
            floating = ids
        case "gaps_in": return needNum { windowMarginSize = $0 * 2 }
        case "screen_padding", "gaps_out":
            return needNum { paddingLeft = $0; paddingRight = $0; paddingTop = $0; paddingBottom = $0 }
        case "enabled":
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
