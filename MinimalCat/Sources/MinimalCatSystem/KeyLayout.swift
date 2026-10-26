import AppKit
import Carbon.HIToolbox
import MinimalCatCore

/// Finds each binding's key on the current keyboard layout, so Z means the key that types z on a German,
/// French or Norwegian keyboard too.
public enum KeyLayout {
    public static func commands() -> [UInt16: Command] {
        let typed = charactersByCode()
        var table: [UInt16: Command] = [:]
        for binding in Command.bindings {
            switch binding.key {
            case .code(let code): table[code] = binding.command
            case .character(let character):
                if let code = typed.first(where: { $0.value == character })?.key ?? ansi[character] {
                    table[code] = binding.command
                }
            }
        }
        return table
    }

    /// The label the current layout prints on the key for a binding.
    public static func label(_ binding: Command.Binding) -> String {
        guard case .character(let character) = binding.key else { return binding.label }
        return String(character).uppercased()
    }

    private static let ansi: [Character: UInt16] = [
        "z": UInt16(kVK_ANSI_Z), "y": UInt16(kVK_ANSI_Y), ",": UInt16(kVK_ANSI_Comma), ".": UInt16(kVK_ANSI_Period)
    ]

    private static func charactersByCode() -> [UInt16: Character] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var result: [UInt16: Character] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in UInt16(0)..<128 {
                var deadKeys: UInt32 = 0, length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count,
                                            &length, &chars)
                guard status == noErr, length == 1, let scalar = Unicode.Scalar(chars[0]) else { continue }
                let character = Character(String(scalar).lowercased())
                if result.values.contains(character) { continue }
                result[code] = character
            }
        }
        return result
    }
}
