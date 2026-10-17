import AppKit
import Carbon
import IOKit
import IOKit.ps
import MacKeysCore
import MacKeysUI

extension MacKeyboard {
    func refresh() {
        let dark = NSApp.map { Theme.isDark($0.effectiveAppearance) } ?? false
        let f = Self.resolve(setting, dark: dark)
        let l = Self.layout(shape: Self.physicalShape(), source: Self.inputSourceID())
        guard f != finish || l != layout || keys.isEmpty else { return }
        finish = f
        layout = l
        device = macDevice(finish: f, layout: l)
        let deck = MacDeckLayout(device)
        keys = device.keyboard.keys.map { KeyHintKeyboard.Key($0, layout: deck) }
    }

    static func resolve(_ setting: String, dark: Bool) -> FinishID {
        let v = slug(setting)
        if let f = FinishID.allCases.first(where: { slug($0.name) == v }) { return f }
        let family = familyFor(v) ?? detectedFamily
        if family == detectedFamily, let f = housingFinish(family) { return f }
        return automatic(family, dark: dark)
    }

    static func isValid(_ setting: String) -> Bool {
        let v = slug(setting)
        return v == "auto" || familyFor(v) != nil || FinishID.allCases.contains { slug($0.name) == v }
    }

    static func familyFor(_ slug: String) -> Family? {
        if slug == "imac" { return .mk }
        return Family.allCases.first { familySlug($0) == slug }
    }

    static func familySlug(_ f: Family) -> String {
        switch f {
        case .pro: "macbook-pro"
        case .air: "macbook-air"
        case .neo: "macbook-neo"
        case .mk: "magic-keyboard"
        }
    }

    static func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "·", with: " ").split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .joined(separator: "-")
    }

    static func automatic(_ family: Family, dark: Bool) -> FinishID {
        switch family {
        case .pro: dark ? .proSpaceBlack : .proSilver
        case .air: dark ? .airMidnight : .airSilver
        case .neo: dark ? .neoIndigo : .neoSilver
        case .mk: .imacSilver
        }
    }

    static func productName() -> String? {
        registryString("IODeviceTree:/product", "product-name")
    }

    static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func registryValue(_ path: String, _ key: String) -> Any? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func registryString(_ path: String, _ key: String) -> String? {
        switch registryValue(path, key) {
        case let s as String: return s
        case let d as Data:
            let s = String(decoding: d.prefix { $0 != 0 }, as: UTF8.self)
            return s.isEmpty ? nil : s
        default: return nil
        }
    }

    static func hasBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { ps in
            let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any]
            return d?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    static func housingFinish(_ family: Family) -> FinishID? {
        guard let colour = housingColor?.lowercased() else { return nil }
        let options = FinishID.allCases.filter { $0.model == family }
        func name(_ f: FinishID) -> String { (f.name.components(separatedBy: " · ").last ?? f.name).lowercased() }
        if let named = options.first(where: { colour.contains(name($0)) || name($0).contains(colour) }) { return named }
        guard colour.hasPrefix("#"), let v = UInt32(colour.dropFirst(), radix: 16) else { return nil }
        func deck(_ f: FinishID) -> UInt32 {
            let c = (try? parseColor(getFinish(f).deck[0])) ?? RGBA(r: 0, g: 0, b: 0)
            return UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)
        }
        func distance(_ a: UInt32, _ b: UInt32) -> Int {
            [16, 8, 0].reduce(0) { sum, shift in
                let d = Int((a >> UInt32(shift)) & 0xFF) - Int((b >> UInt32(shift)) & 0xFF)
                return sum + d * d
            }
        }
        return options.min { distance(deck($0), v) < distance(deck($1), v) }
    }

    static func physicalShape() -> Shape {
        switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
        case kKeyboardISO: .iso
        case kKeyboardJIS: .jis
        default: .ansi
        }
    }

}
