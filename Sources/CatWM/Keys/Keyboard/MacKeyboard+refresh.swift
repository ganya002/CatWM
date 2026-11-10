import AppKit
import Carbon
import CatWMKit
import IOKit
import IOKit.ps
import MacKeysCore
import MacKeysUI

extension MacKeyboard {
    func refresh() {
        let dark = NSApp.map { Theme.isDark($0.effectiveAppearance) } ?? false
        let resolved = Self.resolve(setting, dark: dark)
        let resolvedLayout = Self.layout(shape: Self.physicalShape(), source: Self.inputSourceID())
        guard resolved != finish || resolvedLayout != layout || keys.isEmpty else { return }
        finish = resolved
        layout = resolvedLayout
        device = macDevice(finish: resolved, layout: resolvedLayout)
        let deck = MacDeckLayout(device)
        keys = device.keyboard.keys.map { KeyHintKeyboard.Key($0, layout: deck) }
    }

    static func resolve(_ setting: String, dark: Bool) -> FinishID {
        let wanted = slug(setting)
        if let named = FinishID.allCases.first(where: { slug($0.name) == wanted }) { return named }
        let family = familyFor(wanted) ?? detectedFamily
        if family == detectedFamily, let housing = housingFinish(family) { return housing }
        return automatic(family, dark: dark)
    }

    static func familyFor(_ slug: String) -> Family? {
        if slug == "imac" { return .mk }
        return Family.allCases.first { familySlug($0) == slug }
    }

    static func familySlug(_ family: Family) -> String {
        switch family {
        case .pro: "macbook-pro"
        case .air: "macbook-air"
        case .neo: "macbook-neo"
        case .mk: "magic-keyboard"
        }
    }

    static func slug(_ text: String) -> String { KeyboardFinish.slug(text) }

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
        case let text as String: return text
        case let data as Data:
            let text = String(bytes: data.prefix { $0 != 0 }, encoding: .utf8) ?? ""
            return text.isEmpty ? nil : text
        default: return nil
        }
    }

    static func hasBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    static func housingFinish(_ family: Family) -> FinishID? {
        guard let colour = housingColor?.lowercased() else { return nil }
        let options = FinishID.allCases.filter { $0.model == family }
        func name(_ finish: FinishID) -> String {
            (finish.name.components(separatedBy: " · ").last ?? finish.name).lowercased()
        }
        if let named = options.first(where: { colour.contains(name($0)) || name($0).contains(colour) }) { return named }
        guard colour.hasPrefix("#"), let target = UInt32(colour.dropFirst(), radix: 16) else { return nil }
        func deck(_ finish: FinishID) -> UInt32 {
            let color = (try? parseColor(getFinish(finish).deck[0])) ?? RGBA(r: 0, g: 0, b: 0)
            return UInt32(color.r) << 16 | UInt32(color.g) << 8 | UInt32(color.b)
        }
        func distance(_ first: UInt32, _ second: UInt32) -> Int {
            [16, 8, 0].reduce(0) { sum, shift in
                let delta = Int((first >> UInt32(shift)) & 0xFF) - Int((second >> UInt32(shift)) & 0xFF)
                return sum + delta * delta
            }
        }
        return options.min { distance(deck($0), target) < distance(deck($1), target) }
    }

    static func physicalShape() -> Shape {
        switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
        case kKeyboardISO: .iso
        case kKeyboardJIS: .jis
        default: .ansi
        }
    }
}
