import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

enum ConfigKind: String, Codable, CaseIterable {
    case keyboard, animation, full

    var title: String {
        switch self { case .keyboard: "Keyboard"; case .animation: "Animation"; case .full: "Full" }
    }
    /// What the user is editing, for "Create a new config to edit …".
    var noun: String {
        switch self { case .keyboard: "shortcuts"; case .animation: "animations"; case .full: "settings" }
    }
    var genericSymbol: String {
        switch self { case .keyboard: "keyboard"; case .animation: "wand.and.stars"; case .full: "square.stack.3d.up" }
    }
}

/// A named, saved set of settings. `text` is config-file text: variables and binds for keyboard,
/// the animation options for animation, and the whole file for full.
struct SavedConfig: Codable, Identifiable, Equatable {
    var id: String
    var kind: ConfigKind
    var name: String
    var symbol: String?
    /// RRGGBBAA, nil for no background.
    var colorHex: String?
    var text: String
    /// Full configs remember which keyboard and animation configs were selected.
    var keyboardID: String?
    var animationID: String?

    var isBuiltIn: Bool { id.hasPrefix(ConfigLibrary.builtInPrefix) }
}

/// The file Import and Export read and write: one config, plus the configs a full config links to.
struct ConfigBundle: Codable {
    var app = "ouch"
    var version = 1
    var config: SavedConfig
    var included: [SavedConfig] = []
}

extension UTType {
    static let ouchConfig = UTType(filenameExtension: "ouchconfig", conformingTo: .json) ?? .json
}

// MARK: - Sheets

enum ConfigSheet: Identifiable {
    case create(kind: ConfigKind, baseID: String)
    case edit(id: String)
    case protectedEdit(kinds: [ConfigKind])
    case export(kind: ConfigKind)

    var id: String {
        switch self {
        case .create(let k, let b): "create.\(k.rawValue).\(b)"
        case .edit(let id): "edit.\(id)"
        case .protectedEdit: "protected"
        case .export(let k): "export.\(k.rawValue)"
        }
    }
}

// MARK: - Library

/// Owns every saved config and which one is active per kind. The active config follows the live
/// settings: changes are written into it, except for built-ins, which ask for a copy first.
final class ConfigLibrary: ObservableObject {
    static let builtInPrefix = "builtin."
    static let reservedNames: [ConfigKind: [String]] = [.keyboard: ["Default", "WASD"], .animation: ["Default"], .full: ["Default"]]

    @Published private(set) var custom: [SavedConfig] = []
    @Published private(set) var active: [ConfigKind: String] = [:]
    @Published var sheet: ConfigSheet?

    private let doc: ConfigDocument
    private var builtIns: [SavedConfig] = []
    private var observer: AnyCancellable?
    private var applying = false

    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ouch/configs.json")

    init(doc: ConfigDocument) {
        self.doc = doc
        builtIns = Self.makeBuiltIns()
        load()
        observer = doc.objectWillChange
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in self?.reconcile() }
    }

    // MARK: Built-ins

    private static func makeBuiltIns() -> [SavedConfig] {
        func normalised(_ text: String) -> ConfigDocument { ConfigDocument(text: text) }
        let def = normalised(defaultText), wasd = normalised(wasdText)
        func make(_ id: String, _ kind: ConfigKind, _ name: String, _ text: String, kb: String? = nil, an: String? = nil) -> SavedConfig {
            SavedConfig(id: builtInPrefix + id, kind: kind, name: name, symbol: nil, colorHex: nil, text: text, keyboardID: kb, animationID: an)
        }
        return [
            make("keyboard.default", .keyboard, "Default", def.keyboardText()),
            make("keyboard.wasd", .keyboard, "WASD", wasd.keyboardText()),
            make("animation.default", .animation, "Default", def.animationText()),
            make("full.default", .full, "Default", def.serialize(), kb: builtInPrefix + "keyboard.default", an: builtInPrefix + "animation.default"),
        ]
    }

    func configs(_ kind: ConfigKind) -> [SavedConfig] {
        builtIns.filter { $0.kind == kind } + custom.filter { $0.kind == kind }
    }
    func config(id: String?) -> SavedConfig? {
        guard let id else { return nil }
        return builtIns.first { $0.id == id } ?? custom.first { $0.id == id }
    }
    func current(_ kind: ConfigKind) -> SavedConfig {
        config(id: active[kind]) ?? configs(kind)[0]
    }
    func isActive(_ c: SavedConfig) -> Bool { active[c.kind] == c.id }

    // MARK: Persistence

    private struct Stored: Codable { var custom: [SavedConfig]; var active: [String: String] }

    private func load() {
        if let data = try? Data(contentsOf: Self.url), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            custom = stored.custom
            for (k, v) in stored.active { if let kind = ConfigKind(rawValue: k) { active[kind] = v } }
        } else {
            adoptCurrentSettings()
        }
        for kind in ConfigKind.allCases where config(id: active[kind]) == nil { active[kind] = configs(kind)[0].id }
    }

    private func save() {
        let stored = Stored(custom: custom, active: Dictionary(uniqueKeysWithValues: active.map { ($0.key.rawValue, $0.value) }))
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.url, options: .atomic)
    }

    /// First launch: the settings people already have become the active configs. If they match a built-in
    /// they just start on it, otherwise they're kept as "My config".
    private func adoptCurrentSettings() {
        for kind in ConfigKind.allCases {
            let text = extract(kind)
            if let match = builtIns.first(where: { $0.kind == kind && $0.text == text }) {
                active[kind] = match.id
            } else {
                let mine = SavedConfig(id: UUID().uuidString, kind: kind, name: "My config", symbol: nil, colorHex: nil, text: text)
                custom.append(mine)
                active[kind] = mine.id
            }
        }
        refreshLinks()
        save()
    }

    // MARK: Live settings <-> configs

    private func extract(_ kind: ConfigKind) -> String {
        switch kind {
        case .keyboard: doc.keyboardText()
        case .animation: doc.animationText()
        case .full: doc.serialize()
        }
    }

    /// Text of a full config with the keyboard and animation parts left out. A built-in full config
    /// only guards these other settings, since the other two have their own configs.
    private func otherSettings(_ text: String) -> String {
        ConfigDocument(text: text).serialize(includeKeyboard: false, includeAnimation: false)
    }

    private func refreshLinks() {
        guard let i = custom.firstIndex(where: { $0.id == active[.full] }) else { return }
        custom[i].keyboardID = active[.keyboard]
        custom[i].animationID = active[.animation]
    }

    /// Runs after every settings change: custom configs are updated in place, a built-in that no longer
    /// matches asks for a copy.
    private func reconcile() {
        guard !applying, sheet == nil else { return }
        var violated: [ConfigKind] = []
        var changed = false
        for kind in ConfigKind.allCases {
            let current = current(kind)
            let text = extract(kind)
            if current.isBuiltIn {
                let matches = kind == .full ? otherSettings(text) == otherSettings(current.text) : text == current.text
                if !matches { violated.append(kind) }
            } else if let i = custom.firstIndex(where: { $0.id == current.id }), custom[i].text != text {
                custom[i].text = text
                changed = true
            }
        }
        let before = custom
        refreshLinks()
        if changed || before != custom { save() }
        if !violated.isEmpty { sheet = .protectedEdit(kinds: violated) }
    }

    /// Puts a config's settings into the live document. `reconcile` ignores the resulting changes.
    private func apply(_ c: SavedConfig) {
        applying = true
        switch c.kind {
        case .keyboard: doc.applyKeyboard(c.text)
        case .animation: doc.applyAnimation(c.text)
        case .full: doc.applyFull(c.text)
        }
        doc.save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.applying = false }
    }

    // MARK: Actions

    func select(_ c: SavedConfig) {
        apply(c)
        active[c.kind] = c.id
        if c.kind == .full {
            // A full config brings its keyboard and animation selection along.
            active[.keyboard] = config(id: c.keyboardID)?.id ?? builtIns[0].id
            active[.animation] = config(id: c.animationID)?.id ?? Self.builtInPrefix + "animation.default"
        }
        refreshLinks()
        save()
    }

    func uniqueName(_ wanted: String, kind: ConfigKind, ignoring id: String? = nil) -> String {
        let taken = Set(configs(kind).filter { $0.id != id }.map { $0.name.lowercased() })
        let base = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        if !taken.contains(base.lowercased()) { return base }
        var n = 2
        while taken.contains("\(base) (\(n))".lowercased()) { n += 1 }
        return "\(base) (\(n))"
    }

    func isReserved(_ name: String, kind: ConfigKind) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
        return (Self.reservedNames[kind] ?? []).contains { $0.lowercased() == lower }
    }

    /// Adds a config copied from `baseID` and makes it active.
    @discardableResult
    func create(kind: ConfigKind, baseID: String, name: String, symbol: String?, colorHex: String?) -> SavedConfig {
        let base = config(id: baseID) ?? current(kind)
        let c = SavedConfig(id: UUID().uuidString, kind: kind, name: uniqueName(name, kind: kind), symbol: symbol, colorHex: colorHex,
                            text: base.text, keyboardID: base.keyboardID, animationID: base.animationID)
        custom.append(c)
        select(c)
        return c
    }

    /// The edit-a-built-in answer: the live settings (already changed) become new configs, one per kind.
    func createFromEdit(kinds: [ConfigKind], name: String, symbol: String?, colorHex: String?) {
        for kind in kinds {
            let c = SavedConfig(id: UUID().uuidString, kind: kind, name: uniqueName(name, kind: kind), symbol: symbol, colorHex: colorHex,
                                text: extract(kind))
            custom.append(c)
            active[kind] = c.id
        }
        refreshLinks()
        save()
    }

    /// The edit-a-built-in cancel: put the built-ins back.
    func revertEdit(kinds: [ConfigKind]) {
        for kind in kinds { apply(current(kind)) }
    }

    func update(id: String, name: String, symbol: String?, colorHex: String?) {
        guard let i = custom.firstIndex(where: { $0.id == id }) else { return }
        custom[i].name = uniqueName(name, kind: custom[i].kind, ignoring: id)
        custom[i].symbol = symbol
        custom[i].colorHex = colorHex
        save()
    }

    func duplicate(_ c: SavedConfig) {
        var copy = c
        copy.id = UUID().uuidString
        copy.name = uniqueName(c.name, kind: c.kind)
        if c.isBuiltIn { copy.symbol = nil }
        custom.append(copy)
        save()
    }

    func delete(_ c: SavedConfig) {
        guard !c.isBuiltIn else { return }
        let wasActive = isActive(c)
        custom.removeAll { $0.id == c.id }
        if wasActive { select(configs(c.kind)[0]) } else { save() }
    }

    // MARK: Export

    func export(_ c: SavedConfig, to url: URL) throws {
        var bundle = ConfigBundle(config: c)
        if c.kind == .full {
            bundle.included = [c.keyboardID, c.animationID].compactMap { config(id: $0) }.filter { !$0.isBuiltIn }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bundle).write(to: url, options: .atomic)
    }

    func runExportPanel(for c: SavedConfig) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.ouchConfig]
        panel.nameFieldStringValue = "\(c.name).ouchconfig"
        panel.message = "Export “\(c.name)”"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            do { try self?.export(c, to: url) } catch { Self.alert("Couldn't export", error.localizedDescription) }
        }
        if let w = SettingsWindow.shared.window { panel.beginSheetModal(for: w, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    // MARK: Import

    func runImportPanel(only kind: ConfigKind? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.ouchConfig, .json]
        panel.allowsMultipleSelection = false
        panel.message = kind.map { "Choose a \($0.title.lowercased()) config to import" } ?? "Choose a config to import"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            self?.importFile(url, only: kind)
        }
        if let w = SettingsWindow.shared.window { panel.beginSheetModal(for: w, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    func importFile(_ url: URL, only kind: ConfigKind? = nil) {
        guard let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(ConfigBundle.self, from: data), bundle.app == "ouch" else {
            Self.alert("Not a config file", "“\(url.lastPathComponent)” isn't an Ouch config.")
            return
        }
        if let kind, bundle.config.kind != kind {
            let there = bundle.config.kind == .full ? "the sidebar" : "the \(bundle.config.kind.title) pane"
            Self.alert("Wrong kind of config", "This is a \(bundle.config.kind.title.lowercased()) config. Import it from \(there) instead.")
            return
        }
        // Linked configs first, so the full config can point at their new ids.
        var remap: [String: String] = [:]
        var skipped = 0
        var added: [SavedConfig] = []
        for source in bundle.included + [bundle.config] {
            guard let result = importOne(source, remap: remap) else { return } // cancelled
            remap[source.id] = result.config.id
            skipped += result.skipped
            added.append(result.config)
        }
        guard let main = added.last else { return }
        save()
        var detail = "Added “\(main.name)” to your \(main.kind.title.lowercased()) configs."
        if added.count > 1 { detail += "\nIncludes: " + added.dropLast().map(\.name).joined(separator: ", ") }
        if skipped > 0 { detail += "\n\(skipped) setting\(skipped == 1 ? "" : "s") weren't recognised and were skipped." }
        if Self.confirm("Use “\(main.name)” now?", detail, yes: "Use Now", no: "Not Now") { select(main) }
    }

    /// Adds one config from a file, asking what to do about a clashing name. nil means the user cancelled.
    private func importOne(_ source: SavedConfig, remap: [String: String]) -> (config: SavedConfig, skipped: Int)? {
        var c = source
        c.id = UUID().uuidString
        if c.symbol == "ouch" || source.isBuiltIn { c.symbol = nil }
        if let hex = c.colorHex, Self.color(hex: hex) == nil { c.colorHex = nil }
        if source.isBuiltIn { c.colorHex = nil }
        c.name = String(c.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        if c.name.isEmpty { c.name = "Imported" }
        if c.kind == .full {
            c.keyboardID = c.keyboardID.flatMap { remap[$0] ?? ($0.hasPrefix(Self.builtInPrefix) ? $0 : nil) }
            c.animationID = c.animationID.flatMap { remap[$0] ?? ($0.hasPrefix(Self.builtInPrefix) ? $0 : nil) }
        } else {
            c.keyboardID = nil; c.animationID = nil
        }
        // Anything the parser can't place is dropped, and counted.
        let probe = ConfigDocument(text: c.text)
        let skipped = probe.skippedLineCount

        let clash = configs(c.kind).first { $0.name.lowercased() == c.name.lowercased() }
        if let clash {
            let reserved = clash.isBuiltIn || isReserved(c.name, kind: c.kind)
            switch Self.askClash(name: c.name, canOverride: !reserved) {
            case .keepBoth: c.name = uniqueName(c.name, kind: c.kind)
            case .rename:
                guard let name = Self.askName(initial: uniqueName(c.name, kind: c.kind), kind: c.kind, library: self) else { return nil }
                c.name = name
            case .override:
                var replaced = c
                replaced.id = clash.id
                if let i = custom.firstIndex(where: { $0.id == clash.id }) { custom[i] = replaced }
                if isActive(clash) { apply(replaced) }
                return (replaced, skipped)
            case .cancel: return nil
            }
        }
        custom.append(c)
        return (c, skipped)
    }

    // MARK: Dialogs

    private enum Clash { case keepBoth, rename, override, cancel }

    private static func askClash(name: String, canOverride: Bool) -> Clash {
        let a = NSAlert()
        a.messageText = "You already have a config called “\(name)”"
        a.informativeText = canOverride ? "Replace it, rename the new one, or keep both?" : "“\(name)” is built in and can't be replaced. Rename the new one, or keep both?"
        a.addButton(withTitle: "Keep Both")
        a.addButton(withTitle: "Rename…")
        if canOverride { a.addButton(withTitle: "Replace") }
        a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .rename
        case .alertThirdButtonReturn: return canOverride ? .override : .cancel
        default: return .cancel
        }
    }

    private static func askName(initial: String, kind: ConfigKind, library: ConfigLibrary) -> String? {
        let a = NSAlert()
        a.messageText = "Name the imported config"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        a.accessoryView = field
        a.addButton(withTitle: "Import")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : library.uniqueName(name, kind: kind)
    }

    static func alert(_ title: String, _ detail: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        a.runModal()
    }

    static func confirm(_ title: String, _ detail: String, yes: String, no: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        a.addButton(withTitle: yes)
        a.addButton(withTitle: no)
        return a.runModal() == .alertFirstButtonReturn
    }

    // MARK: Colors

    static func color(hex: String) -> Color? {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let hasAlpha = h.count == 8
        let r = Double((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(v & 0xFF) / 255 : 1
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Whether dark text reads better on this color.
    static func prefersDarkText(hex: String) -> Bool {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count >= 6, let v = UInt64(h.prefix(6), radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.62
    }
}

extension ConfigDocument {
    /// Lines the parser kept aside because it doesn't know them.
    var skippedLineCount: Int { extraLineCount }
}
