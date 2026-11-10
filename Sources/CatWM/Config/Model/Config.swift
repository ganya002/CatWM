import AppKit

struct Config {
    var layouts: [Layout] = [.bsp, .wide, .floating, .fullscreen]
    var windowMargins = true
    var windowMarginSize: CGFloat = 10
    var smartWindowMargins = true
    var paddingLeft: CGFloat = 10, paddingRight: CGFloat = 10, paddingTop: CGFloat = 10, paddingBottom: CGFloat = 10
    var mouseFollowsFocus = true
    var focusFollowsMouse = true
    var focusFollowsMouseInModeOnly = true
    var mouseSwapsWindows = true
    var mouseResizesWindows = true
    var splitHandle = true
    var autoHideTabStrip = false
    var tabNotificationBadges = true
    var floating: [String] = []
    var floatingIsDenylist = true
    var floatSmallWindows = true
    var newWindowsToMain = false
    var enablesLayoutHUD = false
    var enablesLayoutHUDOnSpaceChange = true
    var ignoreMenuBar = false
    var disablePaddingOnBuiltinDisplay = true
    var windowResizeStep: CGFloat = 0.05
    var animate = true
    var animationDuration: Double = 0.12
    var animationCurve: AnimationCurve = .easeOut
    var animationBounce: Double = 0.5
    var debugLogging = false
    var perfReports = false
    var virtualWorkspaces = true
    var stayOnWorkspaceAfterClose = true
    var removesEmptyWorkspaces = true
    var workspacesPerDisplay = true
    var sortNudge = 5
    var modeEffect: ModeFX.Style = .draw
    var dimOtherWindows = false
    var dimStrength: CGFloat = 0.5
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
    var bindRows: [BindRow] = []
    var features = Set(Feature.allCases)
    var currentSubmap = ""
    var errors: [String] = []
    var diagnostics: [ConfigDiagnostic] = []

    static let url = Instance.configFolder.appendingPathComponent("catwm.conf")

    static func load() -> Config {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            Log.attempt("create config folder") {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            Log.attempt("write default config") { try defaultText.write(to: url, atomically: true, encoding: .utf8) }
        }
        let config = parse((try? String(contentsOf: url, encoding: .utf8)) ?? defaultText)
        config.errors.forEach { Log.info("config: \($0)") }
        return config
    }

    static func write(option key: String, _ value: String, to url: URL = Self.url) throws {
        let text = FileManager.default.fileExists(atPath: url.path)
            ? try String(contentsOf: url, encoding: .utf8) : defaultText
        let edited = ConfigText(text).setting(option: key, to: value)
        try edited.write(to: url, atomically: true, encoding: .utf8)
    }

    static func parse(_ text: String) -> Config { ConfigText(text).config }

    mutating func reportEmptySubmaps() {
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
        guard let row = BindRow(value: value, kind: repeats ? "binde" : "bind", submap: currentSubmap) else {
            return "bind needs `MODS, key, dispatcher[, args]`"
        }
        switch BindInterpretation.read(row) {
        case .success(let interpreted): bindings.append(contentsOf: interpreted.bindings)
        case .failure(let failure): return failure.message
        }
        return nil
    }
}

extension Config {
    var workspaceBindings: [KeyBinding] {
        guard virtualWorkspaces else { return bindings }
        var defaults = Config.parse("bind = CTRL, 1..0, workspace, 1..10\n"
            + "bind = CTRL, left|right, workspace, r-1|r+1\n"
            + "bind = CTRL SHIFT, 1..0, movetoworkspace, 1..10\n"
            + "bind = CTRL SHIFT, left|right, movetoworkspace, r-1|r+1").bindings
        let configured = Set(bindings.filter(\.submap.isEmpty).map { Hotkeys.key($0.keyCode, $0.mods) })
        defaults.removeAll { configured.contains(Hotkeys.key($0.keyCode, $0.mods)) }
        return defaults + bindings
    }
}

extension Config {
    func changes(from other: Config) -> Set<String> {
        var changed = Set(Options.all.filter { $0.text(self) != $0.text(other) }.map(\.key))
        if layouts != other.layouts { changed.insert("layouts") }
        if floating != other.floating { changed.insert("floating") }
        if mainMod != other.mainMod { changed.insert("mod") }
        if Dictionary(grouping: bindings, by: \.submap) != Dictionary(grouping: other.bindings, by: \.submap) {
            changed.insert("bindings")
        }
        if features != other.features { changed.insert("features") }
        return changed
    }
}
