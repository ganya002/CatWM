import AppKit
import Carbon
import Combine
import SwiftUI

extension ConfigDocument {
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

    static func keyName(for code: UInt16) -> String? {
        if let name = canonicalKeyNames[code] { return name }
        let names = keyCodes.filter { $0.value == code }.map(\.key).filter { $0.allSatisfy { $0.isLetter || $0.isNumber } }
        guard let best = names.max(by: { $0.count < $1.count }) else { return nil }
        return best.count == 1 ? best.uppercased() : best
    }

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

    static func modifierCaps(_ f: NSEvent.ModifierFlags) -> [String] {
        var caps: [String] = []
        if f.contains(.control) { caps.append("⌃") }
        if f.contains(.option) { caps.append("⌥") }
        if f.contains(.shift) { caps.append("⇧") }
        if f.contains(.command) { caps.append("⌘") }
        return caps
    }

    static func capLabel(_ key: String) -> String { keySymbols[key.lowercased()] ?? key.uppercased() }

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
                out.append(KeyAction(code: code, key: p.key, flags: f, arg: p.arg, title: title, symbol: action?.symbol ?? "curlybraces",
                                     category: action?.category ?? .custom, row: row))
            }
        }
        return out
    }
}
