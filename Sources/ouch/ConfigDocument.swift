import AppKit
import Carbon
import Combine
import SwiftUI

struct BindRow: Identifiable, Equatable {
    let id = UUID()
    var mods: String
    var key: String
    var dispatcher: String
    var args: String
    var submap = "" // "" = global; otherwise the mode this bind belongs to
    var kind = "bind" // bind, binde, bindl…
}

struct VarRow: Equatable {
    var name: String
    var value: String
}

// MARK: - Human-readable actions for keybinds

enum ActionCategory: String, CaseIterable, Identifiable {
    case focus = "Focus", move = "Move Windows", layout = "Layout", window = "Window", displays = "Displays"
    case spaces = "Workspaces", commands = "Commands", app = "Ouch", custom = "Custom"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .focus: "scope"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .layout: "rectangle.split.3x1"
        case .window: "macwindow"
        case .displays: "display.2"
        case .spaces: "square.stack.3d.up"
        case .commands: "terminal"
        case .app: "gearshape"
        case .custom: "curlybraces"
        }
    }
    /// Tint for this kind of action on the shortcut map.
    var color: Color {
        switch self {
        case .focus: .blue
        case .move: .purple
        case .layout: .teal
        case .window: .orange
        case .displays: .indigo
        case .spaces: .green
        case .commands: .gray
        case .app: .pink
        case .custom: .brown
        }
    }
}

struct Action: Identifiable {
    let title: String
    let category: ActionCategory
    let dispatcher: String
    let args: String
    let symbol: String
    /// Numbered families (workspaces, layouts) share a submenu in the action menus; `short` is the item's name there.
    var group: String? = nil
    var short: String? = nil
    var id: String { "\(dispatcher) \(args)" }
}

enum Actions {
    static let all: [Action] = {
        var a: [Action] = []
        func add(_ title: String, _ c: ActionCategory, _ d: String, _ args: String = "", _ symbol: String,
                 group: String? = nil, short: String? = nil) {
            a.append(Action(title: title, category: c, dispatcher: d, args: args, symbol: symbol, group: group, short: short))
        }
        for (dir, name, arrow) in [("l", "Left", "left"), ("r", "Right", "right"), ("u", "Up", "up"), ("d", "Down", "down")] {
            add("Focus \(name)", .focus, "movefocus", dir, "arrow.\(arrow)")
        }
        add("Focus Next Window", .focus, "cyclenext", "", "arrow.forward")
        add("Focus Previous Window", .focus, "cyclenext", "prev", "arrow.backward")
        add("Focus Main Window", .focus, "layoutmsg", "focusmaster", "star")
        for (dir, name, arrow) in [("l", "Left", "left"), ("r", "Right", "right"), ("u", "Up", "up"), ("d", "Down", "down")] {
            add("Move Window \(name)", .move, "movewindow", dir, "arrow.\(arrow).square")
        }
        add("Swap With Main Window", .move, "layoutmsg", "swapwithmaster", "star.square")
        add("Swap With Next Window", .move, "swapnext", "", "arrow.left.arrow.right")
        add("Swap With Previous Window", .move, "swapnext", "prev", "arrow.right.arrow.left")
        add("Next Layout", .layout, "cyclelayout", "next", "rectangle.2.swap")
        add("Previous Layout", .layout, "cyclelayout", "prev", "rectangle.2.swap")
        add("Grow Main Pane", .layout, "splitratio", "+0.05", "arrow.left.and.right.square")
        add("Shrink Main Pane", .layout, "splitratio", "-0.05", "arrow.right.and.line.vertical.and.arrow.left")
        add("More Main Windows", .layout, "layoutmsg", "addmaster", "plus.rectangle")
        add("Fewer Main Windows", .layout, "layoutmsg", "removemaster", "minus.rectangle")
        for l in Layout.allCases {
            add("Use \(l.title) Layout", .layout, "layout", l.rawValue, "rectangle.split.2x2", group: "Use Layout", short: l.title)
        }
        add("Toggle Floating", .window, "togglefloating", "", "macwindow.on.rectangle")
        add("Toggle Fullscreen", .window, "fullscreen", "", "arrow.up.left.and.arrow.down.right")
        add("Close Window", .window, "killactive", "", "xmark.square")
        add("Focus Next Display", .displays, "focusmonitor", "+1", "display")
        add("Focus Previous Display", .displays, "focusmonitor", "-1", "display")
        add("Move Window to Next Display", .displays, "movewindow", "mon:+1", "rectangle.portrait.and.arrow.right")
        add("Move Window to Previous Display", .displays, "movewindow", "mon:-1", "rectangle.portrait.and.arrow.right")
        for (dir, name, arrow) in [("l", "Left", "left"), ("r", "Right", "right"), ("u", "Up", "up"), ("d", "Down", "down")] {
            add("Focus Display \(name)", .displays, "focusmonitor", dir, "arrow.\(arrow).to.line")
            add("Move Window to Display \(name)", .displays, "movewindow", "mon:\(dir)", "arrow.\(arrow).square")
        }
        add("Use This Desktop as Home", .spaces, "sethomespace", "", "house")
        for n in 1...10 { add("Workspace \(n)", .spaces, "workspace", "\(n)", "\(n).square", group: "Go to Workspace", short: "Workspace \(n)") }
        add("Previous Workspace", .spaces, "workspace", "previous", "arrow.uturn.backward.square")
        add("Next Workspace", .spaces, "workspace", "+1", "chevron.right.square")
        add("Previous Numbered Workspace", .spaces, "workspace", "-1", "chevron.left.square")
        add("Next Workspace With Windows", .spaces, "workspace", "e+1", "chevron.forward.2")
        for n in 1...10 {
            add("Move Window to Workspace \(n)", .spaces, "movetoworkspace", "\(n)", "\(n).square.fill",
                group: "Move Window to Workspace", short: "Workspace \(n)")
        }
        for n in 1...10 {
            add("Send Window to Workspace \(n)", .spaces, "movetoworkspacesilent", "\(n)", "\(n).square.fill",
                group: "Send Window to Workspace", short: "Workspace \(n)")
        }
        add("Run Command", .commands, "exec", "", "terminal")
        add("Enter Window Mode", .app, "submap", "window", "keyboard")
        add("Leave Mode", .app, "submap", "reset", "escape")
        add("Toggle Tiling", .app, "toggletiling", "", "power")
        add("Retile Windows", .app, "retile", "", "arrow.clockwise")
        add("Reload Config", .app, "reload", "", "arrow.triangle.2.circlepath")
        add("Quit Ouch", .app, "exit", "", "xmark.circle")
        return a
    }()

    static let byCategory: [(ActionCategory, [Action])] = ActionCategory.allCases.compactMap { c in
        let list = all.filter { $0.category == c }
        return list.isEmpty ? nil : (c, list)
    }

    /// A category's actions as menu entries, each numbered family folded into one submenu where it first appears.
    enum MenuEntry: Identifiable {
        case action(Action), group(String, [Action])
        var id: String {
            switch self {
            case .action(let a): a.id
            case .group(let name, _): "group " + name
            }
        }
    }

    static func menuEntries(_ list: [Action]) -> [MenuEntry] {
        var out: [MenuEntry] = []
        for a in list {
            guard let g = a.group else { out.append(.action(a)); continue }
            if !out.contains(where: { $0.id == "group " + g }) { out.append(.group(g, list.filter { $0.group == g })) }
        }
        return out
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().split(separator: " ").joined(separator: " ")
    }

    /// The catalog entry a bind corresponds to, accepting Hyprland's aliases.
    static func match(_ r: BindRow) -> Action? {
        var d = r.dispatcher.lowercased(), x = norm(r.args)
        if d == "exec" { return all.first { $0.dispatcher == "exec" } }
        if d == "swapwindow" { d = "movewindow" }
        if d == "movewindowtomonitor" { d = "movewindow"; x = "mon:" + x }
        if d == "layoutmsg" {
            switch x {
            case "cyclenext": d = "cyclenext"; x = ""
            case "cycleprev": d = "cyclenext"; x = "prev"
            case "swapnext": d = "swapnext"; x = ""
            case "swapprev": d = "swapnext"; x = "prev"
            case "orientationnext": d = "cyclelayout"; x = "next"
            case "orientationprev": d = "cyclelayout"; x = "prev"
            default: break
            }
        }
        if d == "cyclelayout" && x.isEmpty { x = "next" }
        if d == "splitratio", let v = Double(x.replacingOccurrences(of: "+", with: "")) { x = v > 0 ? "+0.05" : "-0.05" }
        if d == "layoutmsg", x.hasPrefix("mfact"), let v = Double(x.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
            d = "splitratio"; x = v > 0 ? "+0.05" : "-0.05"
        }

        return all.first { $0.dispatcher == d && norm($0.args) == x }
    }

    /// Title for a range bind, e.g. "Switch to Space 1…10" or "Focus Left, Down, Up, Right".
    static func rangeSummary(_ r: BindRow) -> (title: String, category: ActionCategory, symbol: String)? {
        guard case .success(let pairs) = BindRange.pairs(key: r.key, dispatcher: r.dispatcher, arg: r.args), pairs.count > 1
        else { return nil }
        let actions = pairs.map { match(BindRow(mods: "", key: "", dispatcher: r.dispatcher, args: $0.arg)) }
        guard let first = actions.first ?? nil else { return nil }
        if Set(pairs.map(\.arg)).count == 1 { return (first.title, first.category, first.symbol) }
        let titles = actions.map { $0?.title ?? "" }
        let lastWords = titles.map { $0.split(separator: " ").last.map(String.init) ?? "" }
        let prefixes = Set(zip(titles, lastWords).map { $0.dropLast($1.count) })
        if titles.allSatisfy({ !$0.isEmpty }), prefixes.count == 1, let prefix = prefixes.first {
            let numeric = lastWords.allSatisfy { Int($0) != nil }
            let tail = numeric ? "\(lastWords.first!)…\(lastWords.last!)" : lastWords.joined(separator: ", ")
            return (prefix + tail, first.category, first.symbol)
        }
        return ("\(r.dispatcher) \(r.args)", first.category, first.symbol)
    }

    /// Dispatchers the window manager understands, for the custom editor.
    static let dispatchers = ["movefocus", "movewindow", "swapwindow", "cyclenext", "swapnext", "layoutmsg", "splitratio",
                              "togglefloating", "fullscreen", "killactive", "exec", "focusmonitor", "movewindowtomonitor",
                              "workspace", "movetoworkspace", "movetoworkspacesilent", "cyclelayout", "layout", "setlayout",
                              "toggletiling", "retile", "reevaluate", "reload", "exit", "submap", "sethomespace"]
}

// MARK: - Document

/// Editable view of the config file used by the settings window. Typed options live in `config`;
/// variables and binds are kept raw so `$mod` references survive a round trip. Changes save
/// themselves shortly after you stop editing.
final class ConfigDocument: ObservableObject {
    @Published var config = Config()
    @Published var vars: [VarRow] = []
    @Published var binds: [BindRow] = []
    @Published private(set) var fileErrors: [String] = []
    @Published private(set) var saveError: String?
    private var savedText = ""
    private var openedText = "" // state when the window was opened, for "Undo All Changes"
    private var extraLines: [String] = [] // lines we don't understand, written back untouched
    private var autosave: AnyCancellable?

    static let modifierChoices: [(value: String, label: String)] = [
        ("ALT", "⌥ Option"), ("SUPER", "⌘ Command"), ("CTRL", "⌃ Control"),
        ("ALT CTRL", "⌃⌥ Control + Option"), ("CTRL SHIFT", "⌃⇧ Control + Shift"), ("SUPER ALT", "⌥⌘ Option + Command"),
        ("SUPER CTRL", "⌃⌘ Control + Command"), 
    ]

    init() {
        load()
        autosave = objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.autosaveIfNeeded() }
    }

    var isDirty: Bool { serialize() != savedText }
    var hasChangesSinceOpen: Bool { serialize() != openedText }

    /// Called when the window opens: pick up hand edits and remember where we started.
    func beginSession() {
        if !isDirty { load() }
        openedText = serialize()
    }

    func undoAllChanges() { apply(text: openedText) }
    func resetEverything() {
        let mod = modValue
        apply(text: defaultText)
        modValue = mod
    }
    func restoreDefaultShortcuts() { useShortcutSet(defaultText) }

    /// Swaps in the shortcuts from a built-in config text, keeping everything else.
    func useShortcutSet(_ text: String) {
        let current = (vars, config, extraLines)
        apply(text: text)
        let defaults = binds
        (vars, config, extraLines) = current
        // The defaults say `$mod`; the user's modifier variable may be named differently ($mainMod).
        if !vars.contains(where: { $0.name.lowercased().contains("mod") }) { vars.insert(VarRow(name: "$mod", value: "ALT"), at: 0) }
        let name = modVarName
        binds = defaults.map { var r = $0; r.mods = Self.replacingModToken(r.mods, with: name); return r }
    }

    /// Replaces whole `$mod` tokens (space/_/+ separated), leaving `$mod2` and friends alone.
    private static func replacingModToken(_ mods: String, with name: String) -> String {
        var out = "", tok = ""
        func flush() { out += tok == "$mod" ? name : tok; tok = "" }
        for ch in mods { if " _+".contains(ch) { flush(); out.append(ch) } else { tok.append(ch) } }
        flush()
        return out
    }

    /// Writes the variables and binds to keybinds-backup-<date>.conf next to the config.
    func backUpShortcuts() -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let url = Config.url.deletingLastPathComponent().appendingPathComponent("keybinds-backup-\(f.string(from: Date())).conf")
        let all = serialize().components(separatedBy: "\n")
        let lines = ["# Ouch keybind backup, \(Date())"] + vars.map { "\($0.name) = \($0.value.replacingOccurrences(of: "#", with: "##"))" } + [""]
            + all.filter { $0.hasPrefix("bind") || $0.hasPrefix("submap") || $0.isEmpty }
        return (try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    // MARK: Main modifier variable

    /// The variable binds use as their modifier ($mod, or Hyprland's $mainMod).
    var modVarName: String { vars.first { $0.name.lowercased().contains("mod") }?.name ?? "$mod" }

    var modValue: String {
        get { vars.first { $0.name == modVarName }?.value ?? "ALT" }
        set {
            if let i = vars.firstIndex(where: { $0.name == modVarName }) { vars[i].value = newValue }
            else { vars.insert(VarRow(name: modVarName, value: newValue), at: 0) }
        }
    }

    // MARK: Load / save

    func load() {
        apply(text: (try? String(contentsOf: Config.url, encoding: .utf8)) ?? defaultText)
        fileErrors = config.errors
        savedText = serialize()
    }

    private func apply(text: String) {
        config = Config.parse(text)
        var newVars: [VarRow] = [], newBinds: [BindRow] = [], extra: [String] = []
        var resolved: [(String, String)] = []
        var submap = ""
        var blocks: [String] = [] // same block tracking as Config.parse

        for raw in text.components(separatedBy: .newlines) {
            var line = stripComment(raw)
            line = line.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("{") { blocks.append(String(line.dropLast()).trimmingCharacters(in: .whitespaces)); continue }
            if line == "}" { _ = blocks.popLast(); continue }
            if line.isEmpty { continue }
            guard let eq = line.firstIndex(of: "=") else { extra.append(raw); continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let lower = key.lowercased()

            if lower == "submap" {
                submap = value.lowercased() == "reset" ? "" : value
                continue
            }
            if key.hasPrefix("$") {
                newVars.removeAll { $0.name == key }
                newVars.append(VarRow(name: key, value: value))
                resolved.append((key, value))
            } else if lower.hasPrefix("bind") {
                guard lower != "bindm" else { extra.append(raw); continue }
                let p = value.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if p.count >= 3 {
                    newBinds.append(BindRow(mods: p[0], key: p[1], dispatcher: p[2].lowercased(), args: p.count > 3 ? p[3] : "",
                                            submap: submap, kind: lower))
                } else {
                    extra.append(raw)
                }
            } else {
                var probe = Config()
                var v = value
                for (k, val) in resolved.sorted(by: { $0.0.count > $1.0.count }) { v = v.replacingOccurrences(of: k, with: val) }
                if probe.apply((blocks + [key]).joined(separator: ":"), v)?.hasPrefix("unknown option") == true { extra.append(raw) }
            }
        }
        if !newVars.contains(where: { $0.name.lowercased().contains("mod") }) {
            newVars.insert(VarRow(name: "$mod", value: "ALT"), at: 0)
        }
        vars = newVars
        binds = newBinds
        extraLines = extra
    }

    private func autosaveIfNeeded() {
        guard isDirty, problemCount == 0 else { return }
        save()
    }

    @discardableResult
    func save() -> Bool {
        let text = serialize()
        do {
            try FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: Config.url, atomically: true, encoding: .utf8)
        } catch {
            if saveError == nil { saveError = error.localizedDescription }
            return false
        }
        savedText = text
        if saveError != nil { saveError = nil }
        WindowManager.shared.reload(showHUD: false)
        let errors = WindowManager.shared.config.errors
        if errors != fileErrors { fileErrors = errors }
        return true
    }

    func serialize() -> String {
        let c = config
        func b(_ v: Bool) -> String { v ? "true" : "false" }
        func n(_ v: CGFloat) -> String { String(format: "%g", Double(v)) }
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "#", with: "##") }
        var out = [
            "# Ouch config. Written by the Settings window; editing by hand is fine too.",
            "# SUPER = Command, ALT = Option, CTRL = Control.",
            "",
        ]
        out += vars.map { "\($0.name) = \(esc($0.value))" }
        out += [
            "",
            "# tall, tall-right, wide, middle-wide, fullscreen, column, row, floating, bsp, 3column-left,",
            "# 3column-middle, 3column-right, two-pane, two-pane-right, widescreen-tall, widescreen-tall-right",
            "layouts = " + c.layouts.map(\.rawValue).joined(separator: ", "),
            "",
            "window-margins = \(b(c.windowMargins))",
            "window-margin-size = \(n(c.windowMarginSize))",
            "smart-window-margins = \(b(c.smartWindowMargins))",
            "screen-padding-left = \(n(c.paddingLeft))",
            "screen-padding-right = \(n(c.paddingRight))",
            "screen-padding-top = \(n(c.paddingTop))",
            "screen-padding-bottom = \(n(c.paddingBottom))",
            "disable-padding-on-builtin-display = \(b(c.disablePaddingOnBuiltinDisplay))",
            "ignore-menu-bar = \(b(c.ignoreMenuBar))",
            "",
            "mouse-follows-focus = \(b(c.mouseFollowsFocus))",
            "focus-follows-mouse = \(b(c.focusFollowsMouse))",
            "mouse-swaps-windows = \(b(c.mouseSwapsWindows))",
            "mouse-resizes-windows = \(b(c.mouseResizesWindows))",
            "new-windows-to-main = \(b(c.newWindowsToMain))",
            "float-small-windows = \(b(c.floatSmallWindows))",
            "window-resize-step = \(n((c.windowResizeStep * 100).rounded()))",
            "enables-layout-hud = \(b(c.enablesLayoutHUD))",
            "enables-layout-hud-on-space-change = \(b(c.enablesLayoutHUDOnSpaceChange))",
            "",
            "floating = " + c.floating.joined(separator: ", "),
            "floating-is-blacklist = \(b(c.floatingIsBlacklist))",
            "",
            "animate = \(b(c.animate))",
            "animation-duration = \(String(format: "%g", (c.animationDuration * 1000).rounded() / 1000))",
            "# ease-out, ease-in-out, linear, spring, bounce, overshoot or cubic-bezier(x1, y1, x2, y2)",
            "animation-curve = \(c.animationCurve.name)",
            "animation-bounce = \(String(format: "%g", (c.animationBounce * 100).rounded() / 100))",
            "",
            "debug-logging = \(b(c.debugLogging))",
            "virtual-workspaces = \(b(c.virtualWorkspaces))",
            "stay-on-workspace-after-close = \(b(c.stayOnWorkspaceAfterClose))",
            "",
            "# bind = MODS, key, dispatcher, args. Binds inside `submap = name` … `submap = reset` only work in",
            "# that mode (entered with the submap dispatcher); single keys are fine there, vim style.",
        ]
        func line(_ r: BindRow) -> String { "\(r.kind) = \(esc(r.mods)), \(esc(r.key)), \(r.dispatcher)" + (r.args.isEmpty ? "" : ", \(esc(r.args))") }
        out += binds.filter { $0.submap.isEmpty }.map(line)
        for mode in submaps where !mode.isEmpty {
            out += ["", "submap = \(mode)"] + binds.filter { $0.submap == mode }.map(line) + ["submap = reset"]
        }
        if !extraLines.isEmpty {
            out += ["", "# Lines Ouch doesn't recognise, kept as-is"] + extraLines
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: Keybind helpers

    func resolvedMods(_ mods: String) -> String {
        var s = mods
        for v in vars.sorted(by: { $0.name.count > $1.name.count }) { s = s.replacingOccurrences(of: v.name, with: v.value) }
        return s
    }

    static func flags(_ mods: String) -> NSEvent.ModifierFlags? {
        var f: NSEvent.ModifierFlags = []
        for t in mods.uppercased().split(whereSeparator: { " _+".contains($0) }) {
            switch t {
            case "SUPER", "CMD", "COMMAND", "WIN", "META", "MOD4": f.insert(.command)
            case "ALT", "OPT", "OPTION", "MOD1": f.insert(.option)
            case "CTRL", "CONTROL": f.insert(.control)
            case "SHIFT": f.insert(.shift)
            default: return nil
            }
        }
        return f
    }

    /// Mods string for a recorded combo, written as `$mod …` when it includes the main modifier.
    func modsString(for f: NSEvent.ModifierFlags) -> String {
        var rest = f
        var parts: [String] = []
        if let main = Self.flags(modValue), !main.isEmpty, f.isSuperset(of: main) {
            parts.append(modVarName)
            rest.subtract(main)
        }
        if rest.contains(.command) { parts.append("SUPER") }
        if rest.contains(.option) { parts.append("ALT") }
        if rest.contains(.control) { parts.append("CTRL") }
        if rest.contains(.shift) { parts.append("SHIFT") }
        return parts.joined(separator: " ")
    }

    enum Severity { case error, warning }

    private static let commonShortcuts: Set<String> = ["q", "w", "c", "v", "x", "z", "a", "s", "t", "n", "h", "m", "f", "p", "o", "r", "tab", "space", "comma"]

    struct Combo: Hashable { let code: UInt16; let flags: UInt }

    /// Every key combo a row binds (several for a range row), or nil if it doesn't parse.
    func combos(_ row: BindRow) -> [Combo]? {
        guard let f = Self.flags(resolvedMods(row.mods)),
              case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) else { return nil }
        var out: [Combo] = []
        for p in pairs {
            guard let code = keyCodes[p.key.lowercased()] else { return nil }
            out.append(Combo(code: code, flags: f.rawValue))
        }
        return out
    }

    func title(_ row: BindRow) -> String {
        Actions.match(row)?.title ?? Actions.rangeSummary(row)?.title ?? "\(row.dispatcher) \(row.args)"
    }

    func issue(_ row: BindRow) -> (severity: Severity, message: String)? {
        guard let f = Self.flags(resolvedMods(row.mods)) else { return (.error, "Unknown modifier in “\(row.mods)”") }
        if row.key.isEmpty { return (.error, "Click the shortcut and press the keys you want") }
        if case .failure(let e) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) {
            return (.error, e.message.prefix(1).uppercased() + e.message.dropFirst())
        }
        guard let mine = combos(row) else { return (.error, "Unknown key in “\(row.key)”") }
        if row.submap.isEmpty, f.subtracting(.shift).isEmpty, !mine.allSatisfy({ SpecialKey.isSwipe($0.code) }) {
            return (.error, "Add ⌥, ⌃ or ⌘, or put this in window mode, otherwise it would block normal typing")
        }
        let mineSet = Set(mine)
        if let other = binds.first(where: { o in
            o.id != row.id && o.submap == row.submap && !(combos(o).map { mineSet.isDisjoint(with: $0) } ?? true)
        }) {
            return (.error, "Overlaps “\(title(other))”")
        }
        if !Actions.dispatchers.contains(row.dispatcher) { return (.error, "Unknown action “\(row.dispatcher)”") }
        if row.dispatcher == "exec" && row.args.trimmingCharacters(in: .whitespaces).isEmpty {
            return (.error, "Enter the command to run")
        }
        // ⌥ alone (or with ⇧) types symbols on many layouts, e.g. ⌥8 is “[” on Norwegian and Swedish.
        if row.submap.isEmpty, f.contains(.option), f.isDisjoint(with: [.command, .control]) {
            let typed = mine.compactMap { c in Self.typedCharacter(keyCode: c.code, flags: f).map { (c, $0) } }
            if let first = typed.first {
                let key = Self.keyName(for: first.0.code) ?? ""
                let caps = prettyShortcut(BindRow(mods: row.mods, key: key, dispatcher: "", args: "")).joined()
                let more = typed.count > 1 ? " (and \(typed.count - 1) more)" : ""
                return (.warning, "\(caps) types “\(first.1)” on your keyboard layout\(more); this bind blocks it")
            }
        }
        if f == .command, !BindRange.isRange(row.key), Self.commonShortcuts.contains(row.key.lowercased()) {
            return (.warning, "Replaces a standard app shortcut (\(prettyShortcut(row).joined()))")
        }
        return nil
    }

    /// What a key types with these modifiers on the current keyboard layout, if it's a visible character.
    static func typedCharacter(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var mods: UInt32 = 0
        if flags.contains(.shift) { mods |= UInt32(shiftKey >> 8) }
        if flags.contains(.option) { mods |= UInt32(optionKey >> 8) }
        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buf -> OSStatus in
            guard let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), mods, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        let visible = s.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        return visible && !s.trimmingCharacters(in: .whitespaces).isEmpty ? s : nil
    }

    /// Modes in the order they first appear, global ("") first.
    var submaps: [String] {
        var seen = [""]
        for b in binds where !seen.contains(b.submap) { seen.append(b.submap) }
        for b in binds where b.dispatcher == "submap" && b.args.lowercased() != "reset" && !seen.contains(b.args) { seen.append(b.args) }
        return seen
    }

    var problemCount: Int { binds.filter { issue($0)?.severity == .error }.count }

    static func keyName(for code: UInt16) -> String? {
        let names = keyCodes.filter { $0.value == code }.map(\.key).filter { $0.allSatisfy { $0.isLetter || $0.isNumber } }
        guard let best = names.max(by: { $0.count < $1.count }) else { return nil }
        return best.count == 1 ? best.uppercased() : best
    }

    /// Keycaps for display, e.g. ["⌥", "⇧", "H"]. A short `h|j|k|l` list gets a cap per key.
    func prettyShortcut(_ row: BindRow) -> [String] {
        guard let f = Self.flags(resolvedMods(row.mods)) else { return [row.mods, row.key] }
        var caps = Self.modifierCaps(f)
        let cap = Self.capLabel
        if row.key.contains("|") {
            let keys = row.key.split(separator: "|").map { cap($0.trimmingCharacters(in: .whitespaces)) }
            if keys.count <= 5 { caps += keys } else { caps.append(keys.joined(separator: " ")) }
        } else if let r = row.key.range(of: "..") {
            let b = row.key[r.upperBound...].drop { $0 == "." }
            caps.append("\(cap(String(row.key[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)))…\(cap(b.trimmingCharacters(in: .whitespaces)))")
        } else {
            caps.append(cap(row.key))
        }
        return caps
    }

    /// ⌃⌥⇧⌘, in the order macOS menus use.
    static func modifierCaps(_ f: NSEvent.ModifierFlags) -> [String] {
        var caps: [String] = []
        if f.contains(.control) { caps.append("⌃") }
        if f.contains(.option) { caps.append("⌥") }
        if f.contains(.shift) { caps.append("⇧") }
        if f.contains(.command) { caps.append("⌘") }
        return caps
    }

    private static let keySymbols = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "enter": "↩", "tab": "⇥",
        "space": "Space", "escape": "⎋", "esc": "⎋", "capslock": "⇪", "caps": "⇪", "caps_lock": "⇪", "backspace": "⌫",
        "delete": "⌦", "comma": ",", "period": ".", "minus": "−", "equal": "=", "bracketleft": "[", "bracketright": "]",
        "semicolon": ";", "apostrophe": "'", "quote": "'", "slash": "/", "backslash": "\\", "grave": "`",
        "pageup": "⇞", "pagedown": "⇟", "home": "↖", "end": "↘",
        "mouse_up": "Scroll ↑", "mouse_down": "Scroll ↓", "mouse_left": "Scroll ←", "mouse_right": "Scroll →",
        "swipe_left": "Swipe ←", "swipe_right": "Swipe →", "swipe_up": "Swipe ↑", "swipe_down": "Swipe ↓",
    ]

    /// How one key name is printed on a keycap.
    static func capLabel(_ key: String) -> String { keySymbols[key.lowercased()] ?? key.uppercased() }

    // MARK: Shortcut map

    /// One key combo and what it does, with range binds split into their keys.
    struct KeyAction: Identifiable {
        let code: UInt16
        let key: String
        let flags: NSEvent.ModifierFlags
        let title: String
        let symbol: String
        let category: ActionCategory
        let row: BindRow
        var isRange: Bool { BindRange.isRange(row.key) }
        var id: String { "\(row.id) \(code)" }
    }

    /// Every combo bound in a mode ("" = global). Rows that don't parse are left out.
    func keyActions(in submap: String) -> [KeyAction] {
        var out: [KeyAction] = []
        for row in binds where row.submap == submap {
            guard let f = Self.flags(resolvedMods(row.mods)),
                  case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) else { continue }
            for p in pairs {
                guard let code = keyCodes[p.key.lowercased()] else { continue }
                let single = BindRow(mods: "", key: "", dispatcher: row.dispatcher, args: p.arg)
                let action = Actions.match(single)
                let title = row.dispatcher == "exec" ? (p.arg.isEmpty ? "Run Command" : "Run “\(p.arg)”")
                    : action?.title ?? "\(row.dispatcher) \(p.arg)".trimmingCharacters(in: .whitespaces)
                out.append(KeyAction(code: code, key: p.key, flags: f, title: title, symbol: action?.symbol ?? "curlybraces",
                                     category: action?.category ?? .custom, row: row))
            }
        }
        return out
    }
}
