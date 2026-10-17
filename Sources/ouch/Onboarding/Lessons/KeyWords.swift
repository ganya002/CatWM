import AppKit

enum KeyWords {
    static func same(_ a: String, _ b: String) -> Bool {
        if let x = Direction(a), let y = Direction(b) { return x == y }
        let la = a.lowercased(), lb = b.lowercased()
        return la == lb || (lb == "prev" && la.hasPrefix("prev"))
    }

    static func dirToken(_ a: String) -> String? {
        switch Direction(a) {
        case .left: "l"
        case .right: "r"
        case .up: "u"
        case .down: "d"
        case nil: nil
        }
    }

    static func dirWord(_ t: String) -> String {
        ["l": "left", "r": "right", "u": "up", "d": "down"][t] ?? t
    }

    static func ratioDirection(_ dispatcher: String, _ arg: String) -> Bool? {
        var a = arg.lowercased().trimmingCharacters(in: .whitespaces)
        if dispatcher == "layoutmsg" {
            guard a.hasPrefix("mfact") else { return nil }
            a = String(a.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if dispatcher != "splitratio" {
            return nil
        }
        guard !a.hasPrefix("exact") else { return nil }
        return !a.hasPrefix("-")
    }

    static func keyWord(_ b: KeyBinding) -> String {
        let key: String
        switch b.keyCode {
        case 43: key = "Comma"
        case 47: key = "Period"
        case 27: key = "Minus"
        case 24: key = "Equals"
        default: key = keyLabel(b.keyCode, long: false)
        }
        return b.mods.isEmpty ? key : "\(modWords(b.mods))-\(key)"
    }

    static func caps(_ b: KeyBinding, long: Bool) -> [String] {
        modLabels(b.mods, long: long) + [keyLabel(b.keyCode, long: long)]
    }

    static func modLabels(_ f: CGEventFlags, long: Bool) -> [String] {
        var out: [String] = []
        if f.contains(.maskControl) { out.append(long ? "⌃ control" : "⌃") }
        if f.contains(.maskAlternate) { out.append(long ? "⌥ option" : "⌥") }
        if f.contains(.maskShift) { out.append(long ? "⇧ shift" : "⇧") }
        if f.contains(.maskCommand) { out.append("⌘") }
        return out
    }

    static func modWords(_ f: CGEventFlags) -> String {
        var out: [String] = []
        if f.contains(.maskControl) { out.append("Control") }
        if f.contains(.maskAlternate) { out.append("Option") }
        if f.contains(.maskShift) { out.append("Shift") }
        if f.contains(.maskCommand) { out.append("Command") }
        return out.isEmpty ? "A key" : out.joined(separator: "-")
    }

    static func keyLabel(_ code: UInt16, long: Bool) -> String {
        switch code {
        case 57: return long ? "⇪ caps lock" : "⇪"
        case 53: return "esc"
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "space"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 43: return ","
        case 47: return "."
        case 27: return "−"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 44: return "/"
        default: return ConfigDocument.keyName(for: code)?.uppercased() ?? "?"
        }
    }

    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = Locale(identifier: "en_US")
        return (f.string(from: n as NSNumber) ?? String(n)).capitalized
    }

    static func list(_ items: [String], or: Bool = false) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + (or ? " or " : " and ") + items.last!
    }
}
