import AppKit
import CatWMKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension ConfigLibrary {
    func importOne(_ source: SavedConfig, remap: [String: String]) -> (config: SavedConfig, skipped: Int)? {
        var imported = source
        imported.id = UUID().uuidString
        if imported.symbol == "ouch" { imported.symbol = nil }
        if let hex = imported.colorHex, Self.color(hex: hex) == nil { imported.colorHex = nil }
        imported.name = String(imported.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        if imported.name.isEmpty { imported.name = "Imported" }
        if imported.kind == .full {
            func relink(_ id: String) -> String? { remap[id] ?? (id.hasPrefix(Self.builtInPrefix) ? id : nil) }
            imported.keyboardID = imported.keyboardID.flatMap(relink)
            imported.animationID = imported.animationID.flatMap(relink)
        } else {
            imported.keyboardID = nil; imported.animationID = nil
        }
        let probe = ConfigDocument(text: imported.text)
        let skipped = probe.skippedLineCount

        let clash = configs(imported.kind).first { $0.name.lowercased() == imported.name.lowercased() }
        if let clash {
            let reserved = clash.isBuiltIn || isReserved(imported.name, kind: imported.kind)
            switch Self.askClash(name: imported.name, canOverride: !reserved) {
            case .keepBoth: imported.name = uniqueName(imported.name, kind: imported.kind)
            case .rename:
                let initial = uniqueName(imported.name, kind: imported.kind)
                guard let name = Self.askName(initial: initial, kind: imported.kind, library: self) else { return nil }
                imported.name = name
            case .override:
                var replaced = imported
                replaced.id = clash.id
                if let i = custom.firstIndex(where: { $0.id == clash.id }) { custom[i] = replaced }
                if isActive(clash) { apply(replaced) }
                return (replaced, skipped)
            case .cancel: return nil
            }
        }
        custom.append(imported)
        return (imported, skipped)
    }

    static func askClash(name: String, canOverride: Bool) -> Clash {
        let alert = NSAlert()
        alert.messageText = "You already have a config called “\(name)”"
        alert.informativeText = canOverride
            ? "Replace it, rename the new one, or keep both?"
            : "“\(name)” is built in and can't be replaced. Rename the new one, or keep both?"
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Rename…")
        if canOverride { alert.addButton(withTitle: "Replace") }
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .rename
        case .alertThirdButtonReturn: return canOverride ? .override : .cancel
        default: return .cancel
        }
    }

    static func askName(initial: String, kind: ConfigKind, library: ConfigLibrary) -> String? {
        let alert = NSAlert()
        alert.messageText = "Name the imported config"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : library.uniqueName(name, kind: kind)
    }

    static func alert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    static func confirm(_ title: String, _ detail: String, yes confirmTitle: String, no cancelTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: cancelTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func color(hex: String) -> Color? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    static func prefersDarkText(hex: String) -> Bool {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count >= 6, let value = UInt64(digits.prefix(6), radix: 16) else { return false }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.62
    }
}
