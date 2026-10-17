import AppKit
import Carbon
import IOKit
import IOKit.ps
import MacKeysCore
import MacKeysUI

extension MacKeyboard {
    static func inputSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    static func layout(shape: Shape, source: String) -> LayoutID {
        if shape == .jis { return .ja }
        let name = source.replacingOccurrences(of: "com.apple.keylayout.", with: "").lowercased()
        func has(_ parts: String...) -> Bool { parts.contains { name.contains($0) } }
        let mapped: LayoutID? =
            has("russian") ? .ru
            : has("korean") ? .ko
            : has("british", "irish") ? .enGB
            : has("german", "austrian") ? .de
            : has("french", "belgian") ? .fr
            : has("spanish") ? .es
            : has("swedish", "finnish") ? .svFI
            : has("norwegian") ? .no
            : has("danish") ? .da
            : has("italian") ? .it
            : has("dutch") ? .nl
            : has("swiss") ? .ch
            : has("portuguese", "brazilian") ? .pt
            : nil
        if shape == .ansi { return mapped == .ru || mapped == .ko ? mapped! : .enUS }
        return mapped ?? .enIntl
    }

}
