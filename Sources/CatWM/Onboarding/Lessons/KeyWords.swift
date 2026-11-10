import AppKit
import CatWMKit

enum KeyWords {
    enum RatioChange { case grow, shrink }

    static func same(_ lhs: String, _ rhs: String) -> Bool {
        if let x = Direction(lhs), let y = Direction(rhs) { return x == y }
        let lowerLHS = lhs.lowercased(), lowerRHS = rhs.lowercased()
        return lowerLHS == lowerRHS || (lowerRHS == "prev" && lowerLHS.hasPrefix("prev"))
    }

    static func dirToken(_ argument: String) -> String? {
        switch Direction(argument) {
        case .left: "l"
        case .right: "r"
        case .upward: "u"
        case .down: "d"
        case nil: nil
        }
    }

    static func dirWord(_ token: String) -> String {
        ["l": "left", "r": "right", "u": "up", "d": "down"][token] ?? token
    }

    static func ratioDirection(_ dispatcher: String, _ arg: String) -> RatioChange? {
        var amount = arg.lowercased().trimmingCharacters(in: .whitespaces)
        if dispatcher == WindowActions.layoutmsg.name {
            guard amount.hasPrefix("mfact") else { return nil }
            amount = String(amount.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if dispatcher != WindowActions.splitratio.name {
            return nil
        }
        guard !amount.hasPrefix("exact") else { return nil }
        return amount.hasPrefix("-") ? .shrink : .grow
    }

    static func keyWord(_ binding: KeyBinding) -> String {
        let key: String
        switch binding.keyCode {
        case 43: key = "Comma"
        case 47: key = "Period"
        case 27: key = "Minus"
        case 24: key = "Equals"
        default: key = keyLabel(binding.keyCode, long: false)
        }
        return binding.mods.isEmpty ? key : "\(modWords(binding.mods))-\(key)"
    }

    static func caps(_ binding: KeyBinding, long: Bool) -> [String] {
        modLabels(binding.mods, long: long) + [keyLabel(binding.keyCode, long: long)]
    }

    static func modLabels(_ flags: CGEventFlags, long: Bool) -> [String] {
        var out: [String] = []
        if flags.contains(.maskControl) { out.append(long ? "⌃ control" : "⌃") }
        if flags.contains(.maskAlternate) { out.append(long ? "⌥ option" : "⌥") }
        if flags.contains(.maskShift) { out.append(long ? "⇧ shift" : "⇧") }
        if flags.contains(.maskCommand) { out.append("⌘") }
        return out
    }

    static func modWords(_ flags: CGEventFlags) -> String {
        var out: [String] = []
        if flags.contains(.maskControl) { out.append("Control") }
        if flags.contains(.maskAlternate) { out.append("Option") }
        if flags.contains(.maskShift) { out.append("Shift") }
        if flags.contains(.maskCommand) { out.append("Command") }
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

    static func count(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return (formatter.string(for: number) ?? String(number)).capitalized
    }

    static func list(_ items: [String], orJoin: Bool = false) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + (orJoin ? " or " : " and ") + last
    }
}
