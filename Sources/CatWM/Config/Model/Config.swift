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
    var splitHandle = true
    var autoHideTabStrip = false
    var tabNotificationBadges = true
    var floating: [String] = []
    var floatingIsDenylist = true
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
    var removesEmptyWorkspaces = true
    var workspacesPerDisplay = false
    var sortNudge = 5
    var modeEffect: ModeFX.Style = .draw
    var dimOtherWindows = false
    var dimStrength: CGFloat = 0.3
    var blurOtherWindows = false
    var blurRadius: CGFloat = 20
    var panelAnimation: PanelMotion = .rise
    var keyboardHelp = true
    var keyboardHelpKey = "?"
    var cursorActions = true
    var templateAppScripting = false
    var switcherInstantJump = true
    var switcherJumpDelay = 300
    var switcherExclude: [String] = []
    var mainMod: CGEventFlags = .maskAlternate
    var keyboardFinish = "auto"
    var bindings: [KeyBinding] = []
    var currentSubmap = ""
    var errors: [String] = []

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/catwm/catwm.conf")

    static func load() -> Config {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? defaultText.write(to: url, atomically: true, encoding: .utf8)
        }
        let config = parse((try? String(contentsOf: url, encoding: .utf8)) ?? defaultText)
        config.errors.forEach { NSLog("CatWM config: %@", $0) }
        return config
    }

    static func write(option key: String, _ value: String) {
        let read = try? String(contentsOf: url, encoding: .utf8)
        guard read != nil || !FileManager.default.fileExists(atPath: url.path) else { return }
        let text = read ?? defaultText
        var lines = text.components(separatedBy: "\n")
        func norm(_ name: String) -> String { name.lowercased().replacingOccurrences(of: "-", with: "_") }
        let existing = lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return false }
            return norm(trimmed[..<equals].trimmingCharacters(in: .whitespaces)) == norm(key)
        }
        if let existing {
            lines[existing] = "\(key) = \(value)"
        } else {
            let firstBind = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("bind") }
            lines.insert("\(key) = \(value)", at: firstBind ?? lines.count)
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func parse(_ text: String) -> Config {
        var config = Config()
        var vars: [(String, String)] = []
        var modVar: String?
        var blocks: [String] = []
        for (index, raw) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            var line = stripComment(String(raw))
            line = line.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("{") {
                blocks.append(String(line.dropLast()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if line == "}" { _ = blocks.popLast(); continue }
            if line.isEmpty { continue }
            guard let equals = line.firstIndex(of: "=") else {
                config.errors.append("line \(index + 1): expected `key = value`")
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            for (name, replacement) in vars { value = value.replacingOccurrences(of: name, with: replacement) }
            if key.hasPrefix("$") {
                vars.removeAll { $0.0 == key }
                vars.append((key, value))
                vars.sort { $0.0.count > $1.0.count }
                if key.lowercased().contains("mod"), (modVar ?? key) == key, let flags = ConfigDocument.flags(value) {
                    modVar = key
                    config.mainMod = CGEventFlags(rawValue: UInt64(flags.rawValue))
                }
                continue
            }
            if key.lowercased() == "submap" {
                config.currentSubmap = value.lowercased() == "reset" ? "" : value
                continue
            }
            if let err = config.apply((blocks + [key]).joined(separator: ":"), value) {
                config.errors.append("line \(index + 1): \(err)")
            }
        }
        config.reportEmptySubmaps()
        return config
    }

    private mutating func reportEmptySubmaps() {
        let modes = Set(bindings.map(\.submap))
        for bind in bindings where bind.dispatcher == "submap" && bind.arg.lowercased() != "reset"
            && !bind.arg.isEmpty && !modes.contains(bind.arg) {
            let near = modes.first { $0.lowercased() == bind.arg.lowercased() }.map { " (did you mean `\($0)`?)" }
            let error = "`submap, \(bind.arg)` enters a mode with no binds\(near ?? "")"
            if !errors.contains(error) { errors.append(error) }
        }
    }

    mutating func apply(_ rawKey: String, _ value: String) -> String? {
        var key = rawKey.lowercased().replacingOccurrences(of: "-", with: "_")
        let fullKey = key
        if let colon = key.lastIndex(of: ":") { key = String(key[key.index(after: colon)...]) }
        func needNum(_ set: (CGFloat) -> Void) -> String? {
            guard let num = Double(value), num.isFinite else { return "`\(rawKey)` needs a number" }
            set(CGFloat(num)); return nil
        }

        switch key {
        case "bind", "binde", "bindr", "bindl", "bindel", "bindle":
            return parseBind(value, repeats: ["binde", "bindel", "bindle"].contains(key))
        case "bindm": return nil
        case "layouts":
            var list: [Layout] = []
            for name in value.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
                guard let layout = Layout(rawValue: name) else { return "unknown layout `\(name)`" }
                if !list.contains(layout) { list.append(layout) }
            }
            if !list.isEmpty { layouts = list }
        case "floating": floating = Self.listItems(value)
        case "gaps_in": return needNum { windowMarginSize = Self.clamped($0 * 2, \.windowMarginSize) }
        case "screen_padding", "gaps_out":
            return needNum {
                let padding = Self.clamped($0, \.paddingLeft)
                paddingLeft = padding; paddingRight = padding; paddingTop = padding; paddingBottom = padding
            }
        case "enabled":
            guard fullKey == "animations:enabled" else { return "unknown option `\(rawKey)`" }
            let (enabled, error) = ConfigOption.readBool(value, rawKey)
            if error == nil { animate = enabled }
            return error
        default:
            guard let option = ConfigOption.named(key) else { return "unknown option `\(rawKey)`" }
            return option.read(&self, value, rawKey)
        }
        return nil
    }

    private static func clamped(_ value: CGFloat, _ path: WritableKeyPath<Config, CGFloat>) -> CGFloat {
        guard let valid = ConfigOption.at(path).valid else { return value }
        return min(CGFloat(valid.upperBound), max(CGFloat(valid.lowerBound), value))
    }

    static func listItems(_ value: String) -> [String] {
        var items: [String] = []
        for item in value.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
        where !item.isEmpty && !items.contains(item) {
            items.append(item)
        }
        return items
    }

    static func lists(_ bundle: String, in patterns: [String]) -> Bool {
        patterns.contains { $0.hasSuffix("*") ? bundle.hasPrefix(String($0.dropLast())) : bundle == $0 }
    }

    private mutating func parseBind(_ value: String, repeats: Bool) -> String? {
        let parts = value.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return "bind needs `MODS, key, dispatcher[, args]`" }
        var mods: CGEventFlags = []
        for modifier in parts[0].uppercased().split(whereSeparator: { " _+".contains($0) }) {
            switch modifier {
            case "SUPER", "CMD", "COMMAND", "WIN", "META", "MOD4": mods.insert(.maskCommand)
            case "ALT", "OPT", "OPTION", "MOD1": mods.insert(.maskAlternate)
            case "CTRL", "CONTROL": mods.insert(.maskControl)
            case "SHIFT": mods.insert(.maskShift)
            default: return "unknown modifier `\(modifier)`"
            }
        }
        let dispatcher = parts[2].lowercased()
        let pairs: [(key: String, arg: String)]
        switch BindRange.pairs(key: parts[1], dispatcher: dispatcher, arg: parts.count > 3 ? parts[3] : "") {
        case .success(let found): pairs = found
        case .failure(let failure): return failure.message
        }
        for (key, arg) in pairs {
            guard let code = keyCodes[key.lowercased()] else { return "unknown key `\(key)`" }
            bindings.append(KeyBinding(keyCode: code, mods: mods, dispatcher: dispatcher, arg: arg,
                                       submap: currentSubmap, repeats: repeats))
        }
        return nil
    }
}
