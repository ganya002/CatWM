import AppKit
import ApplicationServices

enum SystemShortcut {
    struct Combo { let keyCode: UInt16; let flags: CGEventFlags }

    private static func read(_ id: Int) -> (enabled: Bool, combo: Combo)? {
        guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = all[String(id)] as? [String: Any] else { return nil }
        let enabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? NSNumber)?.boolValue ?? false)
        guard let params = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber], params.count == 3 else { return nil }
        return (enabled, Combo(keyCode: params[1].uint16Value, flags: CGEventFlags(rawValue: params[2].uint64Value)))
    }

    static func desktop(_ n: Int) -> Combo? {
        guard (1...16).contains(n), let s = read(117 + n), s.enabled else { return nil }
        return s.combo
    }

    static func step(right: Bool) -> Combo? {
        if let s = read(right ? 81 : 79) { return s.enabled ? s.combo : nil }
        return Combo(keyCode: right ? 124 : 123, flags: [.maskControl, .maskSecondaryFn])
    }
}
