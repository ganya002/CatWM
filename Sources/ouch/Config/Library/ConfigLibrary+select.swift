import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension ConfigLibrary {
    func select(_ c: SavedConfig) {
        apply(c)
        active[c.kind] = c.id
        if c.kind == .full {
            active[.keyboard] = config(id: c.keyboardID)?.id ?? builtIns[0].id
            active[.animation] = config(id: c.animationID)?.id ?? Self.builtInPrefix + "animation.default"
            doc.applyKeyboard(current(.keyboard).text)
            doc.applyAnimation(current(.animation).text)
            doc.save()
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

    @discardableResult
    func create(kind: ConfigKind, baseID: String, name: String, symbol: String?, colorHex: String?) -> SavedConfig {
        let base = config(id: baseID) ?? current(kind)
        let c = SavedConfig(id: UUID().uuidString, kind: kind, name: uniqueName(name, kind: kind), symbol: symbol, colorHex: colorHex,
                            text: base.text, keyboardID: base.keyboardID, animationID: base.animationID)
        custom.append(c)
        select(c)
        return c
    }

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
        var remap: [String: String] = [:]
        var skipped = 0
        var added: [SavedConfig] = []
        for source in bundle.included + [bundle.config] {
            guard let result = importOne(source, remap: remap) else { return }
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

}
