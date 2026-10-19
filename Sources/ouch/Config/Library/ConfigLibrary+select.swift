import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension ConfigLibrary {
    func select(_ saved: SavedConfig) {
        apply(saved)
        active[saved.kind] = saved.id
        if saved.kind == .full {
            active[.keyboard] = config(id: saved.keyboardID)?.id ?? builtIns[0].id
            active[.animation] = config(id: saved.animationID)?.id ?? Self.builtInPrefix + "animation.default"
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
        var suffix = 2
        while taken.contains("\(base) (\(suffix))".lowercased()) { suffix += 1 }
        return "\(base) (\(suffix))"
    }

    func isReserved(_ name: String, kind: ConfigKind) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
        return (Self.reservedNames[kind] ?? []).contains { $0.lowercased() == lower }
    }

    @discardableResult
    func create(kind: ConfigKind, baseID: String, name: String, symbol: String?, colorHex: String?) -> SavedConfig {
        let base = config(id: baseID) ?? current(kind)
        let saved = SavedConfig(id: UUID().uuidString, kind: kind, name: uniqueName(name, kind: kind), symbol: symbol,
                                colorHex: colorHex, text: base.text, keyboardID: base.keyboardID,
                                animationID: base.animationID)
        custom.append(saved)
        select(saved)
        return saved
    }

    func createFromEdit(kinds: [ConfigKind], name: String, symbol: String?, colorHex: String?) {
        for kind in kinds {
            let saved = SavedConfig(id: UUID().uuidString, kind: kind, name: uniqueName(name, kind: kind),
                                    symbol: symbol, colorHex: colorHex, text: extract(kind))
            custom.append(saved)
            active[kind] = saved.id
        }
        refreshLinks()
        save()
    }

    func update(id: String, name: String, symbol: String?, colorHex: String?) {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return }
        custom[index].name = uniqueName(name, kind: custom[index].kind, ignoring: id)
        custom[index].symbol = symbol
        custom[index].colorHex = colorHex
        save()
    }

    func duplicate(_ saved: SavedConfig) {
        var copy = saved
        copy.id = UUID().uuidString
        copy.name = uniqueName(saved.name, kind: saved.kind)
        if saved.isBuiltIn { copy.symbol = nil }
        custom.append(copy)
        save()
    }

    func delete(_ saved: SavedConfig) {
        guard !saved.isBuiltIn else { return }
        let wasActive = isActive(saved)
        custom.removeAll { $0.id == saved.id }
        if wasActive { select(configs(saved.kind)[0]) } else { save() }
    }

    func export(_ saved: SavedConfig, to url: URL) throws {
        var bundle = ConfigBundle(config: saved)
        if saved.kind == .full {
            bundle.included = [saved.keyboardID, saved.animationID].compactMap { config(id: $0) }
                .filter { !$0.isBuiltIn }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bundle).write(to: url, options: .atomic)
    }

    func runExportPanel(for saved: SavedConfig) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.ouchConfig]
        panel.nameFieldStringValue = "\(saved.name).ouchconfig"
        panel.message = "Export “\(saved.name)”"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try self?.export(saved, to: url) } catch { Self.alert("Couldn't export", error.localizedDescription) }
        }
        if let window = SettingsWindow.shared.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    func runImportPanel(only kind: ConfigKind? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.ouchConfig, .json]
        panel.allowsMultipleSelection = false
        panel.message = kind.map { "Choose a \($0.title.lowercased()) config to import" } ?? "Choose a config to import"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importFile(url, only: kind)
        }
        if let window = SettingsWindow.shared.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    func importFile(_ url: URL, only kind: ConfigKind? = nil) {
        guard let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(ConfigBundle.self, from: data), bundle.app == "ouch" else {
            Self.alert("Not a config file", "“\(url.lastPathComponent)” isn't an Ouch config.")
            return
        }
        if let kind, bundle.config.kind != kind {
            let there = bundle.config.kind == .full ? "the sidebar" : "the \(bundle.config.kind.title) pane"
            Self.alert("Wrong kind of config",
                       "This is a \(bundle.config.kind.title.lowercased()) config. Import it from \(there) instead.")
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
        if skipped > 0 {
            detail += "\n\(skipped) setting\(skipped == 1 ? "" : "s") weren't recognised and were skipped."
        }
        if Self.confirm("Use “\(main.name)” now?", detail, yes: "Use Now", no: "Not Now") { select(main) }
    }
}
