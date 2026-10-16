// Keys: this Mac's keyboard for the MacKeys SDK: model, finish, physical layout and input-source layout.
import AppKit
import Carbon
import IOKit
import IOKit.ps
import MacKeysCore
import MacKeysUI

/// The keyboard KeyHintKeyboard draws, as a MacKeys `MacDevice`: this Mac's model and finish (and its
/// housing colour when the IORegistry has one), the layout of its physical keyboard (ANSI, ISO or JIS)
/// and the input source in use. Follows input source and Light/Dark changes. `keyboard-finish` in the
/// config picks another finish or family.
final class MacKeyboard: ObservableObject {
    static let shared = MacKeyboard()

    typealias Family = ModelID

    enum Shape { case ansi, iso, jis }

    @Published private(set) var finish: FinishID
    @Published private(set) var layout: LayoutID = .enUS
    @Published private(set) var device: MacDevice
    @Published private(set) var keys: [KeyHintKeyboard.Key] = []

    var deckLayout: MacDeckLayout { MacDeckLayout(device) }

    /// `auto`, a finish (`macbook-air-midnight`) or a family (`macbook-pro`). Set from the config.
    var setting = "auto" {
        didSet { if setting != oldValue { refresh() } }
    }

    private var appearanceObserver: NSKeyValueObservation?

    private init() {
        let f = FinishID.proSpaceBlack
        finish = f
        device = macDevice(finish: f, layout: .enUS)
        refresh()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        // Another keyboard (an ISO one plugged in) shows up as a new keyboard type on the next key press.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        appearanceObserver = NSApp?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    /// Reads the model, finish and layout again; publishes only what changed.
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

    // MARK: Model and finish

    /// What this Mac is: the product name on Apple silicon ("MacBook Air (13-inch, M4, 2025)"), the
    /// model identifier on Intel ("MacBookPro16,1"). A laptop we can't name gets the Air; a desktop the
    /// Magic Keyboard.
    static let detectedFamily: Family = {
        let name = ((productName() ?? "") + " " + (sysctl("hw.model") ?? "")).lowercased()
        if name.contains("macbook pro") || name.contains("macbookpro") { return .pro }
        if name.contains("macbook neo") || name.contains("macbookneo") { return .neo }
        if name.contains("macbook") { return .air }
        for desktop in ["imac", "mac mini", "macmini", "mac studio", "macstudio", "mac pro", "macpro"] where name.contains(desktop) {
            return .mk
        }
        return hasBattery() ? .air : .mk
    }()

    /// The finish for a config value. `auto` uses this Mac's family and its housing colour when the
    /// IORegistry names one, otherwise a finish that suits Light or Dark Mode.
    static func resolve(_ setting: String, dark: Bool) -> FinishID {
        let v = slug(setting)
        if let f = FinishID.allCases.first(where: { slug($0.name) == v }) { return f }
        let family = familyFor(v) ?? detectedFamily
        if family == detectedFamily, let f = housingFinish(family) { return f }
        return automatic(family, dark: dark)
    }

    /// Whether `keyboard-finish` understands the value.
    static func isValid(_ setting: String) -> Bool {
        let v = slug(setting)
        return v == "auto" || familyFor(v) != nil || FinishID.allCases.contains { slug($0.name) == v }
    }

    private static func familyFor(_ slug: String) -> Family? {
        if slug == "imac" { return .mk }
        return Family.allCases.first { familySlug($0) == slug }
    }

    private static func familySlug(_ f: Family) -> String {
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

    /// Without a known housing colour: the dark finish in Dark Mode, silver in Light Mode.
    private static func automatic(_ family: Family, dark: Bool) -> FinishID {
        switch family {
        case .pro: dark ? .proSpaceBlack : .proSilver
        case .air: dark ? .airMidnight : .airSilver
        case .neo: dark ? .neoIndigo : .neoSilver
        case .mk: .imacSilver
        }
    }

    private static func productName() -> String? {
        registryString("IODeviceTree:/product", "product-name")
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    private static func registryValue(_ path: String, _ key: String) -> Any? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func registryString(_ path: String, _ key: String) -> String? {
        switch registryValue(path, key) {
        case let s as String: return s
        case let d as Data:
            let s = String(decoding: d.prefix { $0 != 0 }, as: UTF8.self)
            return s.isEmpty ? nil : s
        default: return nil
        }
    }

    private static func hasBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { ps in
            let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any]
            return d?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    /// The housing colour, if the IORegistry exposes one: a name ("blue") or an RGB triple.
    static let housingColor: String? = {
        for path in ["IODeviceTree:/product", "IODeviceTree:/"] {
            for key in ["housing-color", "device-color", "enclosure-color", "DeviceEnclosureColor"] {
                switch registryValue(path, key) {
                case let s as String where !s.isEmpty: return s
                case let d as Data where !d.isEmpty:
                    let text = String(decoding: d.prefix { $0 != 0 }, as: UTF8.self)
                    if text.count > 1, text.allSatisfy({ $0.isLetter || $0 == " " }) { return text }
                    if d.count >= 3 { return String(format: "#%02x%02x%02x", d[0], d[1], d[2]) }
                case let n as NSNumber: return String(format: "#%06x", n.uint32Value & 0xFFFFFF)
                default: continue
                }
            }
        }
        return nil
    }()

    /// The family's finish closest to the housing colour: by name, or the nearest deck colour.
    private static func housingFinish(_ family: Family) -> FinishID? {
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

    // MARK: Layout and input source

    private static func physicalShape() -> Shape {
        switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
        case kKeyboardISO: .iso
        case kKeyboardJIS: .jis
        default: .ansi
        }
    }

    private static func inputSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// The MacKeys layout for the physical keyboard and the input source in use. A JIS keyboard is
    /// always Japanese; an ANSI one shows the source's layout only where that layout has no ISO key
    /// (US English and Korean) or is non-Latin (Russian); an ISO one shows the source's own layout.
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
