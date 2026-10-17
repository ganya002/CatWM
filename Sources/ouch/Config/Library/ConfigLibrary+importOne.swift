import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension ConfigLibrary {
    func importOne(_ source: SavedConfig, remap: [String: String]) -> (config: SavedConfig, skipped: Int)? {
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

    static func askClash(name: String, canOverride: Bool) -> Clash {
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

    static func askName(initial: String, kind: ConfigKind, library: ConfigLibrary) -> String? {
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

    static func prefersDarkText(hex: String) -> Bool {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count >= 6, let v = UInt64(h.prefix(6), radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.62
    }
}
