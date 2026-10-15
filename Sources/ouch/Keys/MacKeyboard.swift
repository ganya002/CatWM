// Keys: this Mac's keyboard model, finish, physical layout and input-source legends.
import AppKit
import Carbon
import IOKit
import IOKit.ps

/// The keyboard KeyHintKeyboard draws: this Mac's keycaps and finish (from its model, and its housing
/// colour when the IORegistry has one), its physical layout (ANSI, ISO or JIS) and the legends of the
/// input source in use. Follows input source and Light/Dark changes. `keyboard-finish` in the config
/// picks another finish or family.
///
/// Geometry is in the points of the Mac Keyboard design artifact: a 1u key on a 64pt pitch, 58pt wide
/// with a 6pt gap, 56pt tall, rows 62pt apart. KeyHintKeyboard scales it.
final class MacKeyboard: ObservableObject {
    static let shared = MacKeyboard()

    enum Family: String, CaseIterable {
        /// MacBook Pro, MacBook Air, MacBook Neo, and the Magic Keyboard of the desktops.
        case pro, air, neo, mk

        var slug: String {
            switch self {
            case .pro: "macbook-pro"
            case .air: "macbook-air"
            case .neo: "macbook-neo"
            case .mk: "magic-keyboard"
            }
        }
    }

    enum Shape { case ansi, iso, jis }

    @Published private(set) var finish: Finish
    @Published private(set) var shape: Shape = .ansi
    @Published private(set) var keys: [KeyHintKeyboard.Key] = []

    /// `auto`, a finish (`macbook-air-midnight`) or a family (`macbook-pro`). Set from the config.
    var setting = "auto" {
        didSet { if setting != oldValue { refresh() } }
    }

    private var appearanceObserver: NSKeyValueObservation?
    private var sourceSignature = ""

    private init() {
        finish = Finish.all[0]
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

    /// Reads the model, finish, layout and legends again; publishes only what changed.
    func refresh() {
        let dark = NSApp.map { Theme.isDark($0.effectiveAppearance) } ?? false
        let f = Self.resolve(setting, dark: dark)
        let s = Self.physicalShape()
        let source = Self.inputSourceID()
        let signature = "\(source) \(s) \(f.name)"
        if f != finish { finish = f }
        if s != shape { shape = s }
        guard signature != sourceSignature || keys.isEmpty else { return }
        sourceSignature = signature
        let english = s == .ansi && Self.englishSources.contains(source)
        let typed = Self.typingLegends()
        keys = Self.build(shape: s, light: f.lightKeys, english: english, legends: typed.legends, koreanCaps: typed.koreanCaps)
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
    static func resolve(_ setting: String, dark: Bool) -> Finish {
        let v = slug(setting)
        if let f = Finish.all.first(where: { $0.slug == v }) { return f }
        let family = familyFor(v) ?? detectedFamily
        if family == detectedFamily, let f = housingFinish(family) { return f }
        return Finish.automatic(family, dark: dark)
    }

    /// Whether `keyboard-finish` understands the value.
    static func isValid(_ setting: String) -> Bool {
        let v = slug(setting)
        return v == "auto" || familyFor(v) != nil || Finish.all.contains { $0.slug == v }
    }

    private static func familyFor(_ slug: String) -> Family? {
        if slug == "imac" { return .mk }
        return Family.allCases.first { $0.slug == slug }
    }

    static func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "·", with: " ").split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .joined(separator: "-")
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
    private static func housingFinish(_ family: Family) -> Finish? {
        guard let colour = housingColor?.lowercased() else { return nil }
        let options = Finish.all.filter { $0.family == family }
        if let named = options.first(where: { colour.contains($0.colour.lowercased()) || $0.colour.lowercased().contains(colour) }) {
            return named
        }
        guard colour.hasPrefix("#"), let v = UInt32(colour.dropFirst(), radix: 16) else { return nil }
        func distance(_ a: UInt32, _ b: UInt32) -> Int {
            [16, 8, 0].reduce(0) { sum, shift in
                let d = Int((a >> UInt32(shift)) & 0xFF) - Int((b >> UInt32(shift)) & 0xFF)
                return sum + d * d
            }
        }
        return options.min { distance($0.deck.0, v) < distance($1.deck.0, v) }
    }

    // MARK: Layout and legends

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

    /// US English layouts: the only ones whose keyboards print words (tab, shift, command) on the keys.
    private static let englishSources: Set<String> = [
        "com.apple.keylayout.US", "com.apple.keylayout.ABC", "com.apple.keylayout.USExtended",
        "com.apple.keylayout.Dvorak", "com.apple.keylayout.DVORAK-QWERTYCMD", "com.apple.keylayout.Colemak",
    ]

    /// The letter keys, by key code.
    private static let letters: [UInt16: String] = [
        12: "Q", 13: "W", 14: "E", 15: "R", 17: "T", 16: "Y", 32: "U", 34: "I", 31: "O", 35: "P",
        0: "A", 1: "S", 2: "D", 3: "F", 5: "G", 4: "H", 38: "J", 40: "K", 37: "L",
        6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 45: "N", 46: "M",
    ]
    /// The other typing keys on a US keyboard: base and shifted. 10 is the ISO key left of 1.
    private static let usSymbols: [UInt16: (String, String)] = [
        50: ("`", "~"), 18: ("1", "!"), 19: ("2", "@"), 20: ("3", "#"), 21: ("4", "$"), 23: ("5", "%"), 22: ("6", "^"),
        26: ("7", "&"), 28: ("8", "*"), 25: ("9", "("), 29: ("0", ")"), 27: ("-", "_"), 24: ("=", "+"),
        33: ("[", "{"), 30: ("]", "}"), 42: ("\\", "|"), 41: (";", ":"), 39: ("'", "\""),
        43: (",", "<"), 47: (".", ">"), 44: ("/", "?"), 10: ("§", "±"),
    ]

    private static func isLetter(_ s: String) -> Bool { s.count == 1 && s.uppercased() != s.lowercased() }
    private static func isLatin(_ s: String) -> Bool {
        guard let v = s.unicodeScalars.first?.value else { return true }
        return v < 0x250 || (0x1E00...0x1EFF).contains(v)
    }

    /// What the typing keys say on the current input source: a letter, or the shifted symbol over the
    /// base one. Some Latin layouts also print an Option symbol on letter keys. A non-Latin layout
    /// (Russian, Greek) keeps the Latin legends on the left and adds its own on the right, as those
    /// keyboards are printed.
    static func typingLegends() -> (legends: [UInt16: KeyHintKeyboard.Legend], koreanCaps: Bool) {
        let codes = Array(letters.keys) + Array(usSymbols.keys)
        var native: [UInt16: (base: String, shifted: String?, option: String?)] = [:]
        for c in codes {
            guard let base = ConfigDocument.typedCharacter(keyCode: c, flags: []) else { continue }
            native[c] = (base, ConfigDocument.typedCharacter(keyCode: c, flags: .shift), ConfigDocument.typedCharacter(keyCode: c, flags: .option))
        }
        let nonLatin = letters.keys.contains { native[$0].map { isLetter($0.base) && !isLatin($0.base) } ?? false }
        let koreanCaps = letters.keys.contains {
            native[$0].map {
                $0.base.unicodeScalars.contains { (0x1100...0x11FF).contains($0.value) || (0x3130...0x318F).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
            } ?? false
        }
        var out: [UInt16: KeyHintKeyboard.Legend] = [:]
        for c in codes {
            let us: (base: String, shifted: String?) = letters[c].map { ($0.lowercased(), $0) } ?? usSymbols[c].map { ($0.0, $0.1) } ?? ("", nil)
            guard let n = native[c] else { out[c] = plain(us.base, us.shifted, nil); continue }
            if nonLatin, n.base.lowercased() != us.base.lowercased() || n.shifted != us.shifted {
                out[c] = quad(code: c, us: us, native: n)
            } else {
                out[c] = plain(n.base, n.shifted, n.option)
            }
        }
        return (out, koreanCaps)
    }

    private static func plain(_ base: String, _ shifted: String?, _ option: String?) -> KeyHintKeyboard.Legend {
        if isLetter(base), shifted == nil || shifted == base.uppercased() {
            if let option, printedOption.contains(option) {
                return .init(t: base.uppercased(), c: option, kind: .charOption)
            }
            return .init(t: base.uppercased())
        }
        if let shifted, shifted != base { return .init(t: shifted, b: base, kind: .dual) }
        return .init(t: base.uppercased())
    }

    /// Option characters Apple prints on letter keys (€ on E, @ on L for German, Spanish, Italian…).
    /// Others, like US ∂ or ƒ, are typeable but not printed.
    private static let printedOption: Set<String> = ["€", "@"]

    private static func quad(code: UInt16, us: (base: String, shifted: String?), native n: (base: String, shifted: String?, option: String?)) -> KeyHintKeyboard.Legend {
        var l = KeyHintKeyboard.Legend(kind: .quad)
        if let letter = letters[code] { l.t = letter } else { l.t = us.shifted ?? ""; l.b = us.base }
        if isLetter(n.base) {
            l.c = n.base.uppercased()
        } else {
            if n.shifted != us.shifted { l.d = n.shifted ?? "" }
            if n.base != us.base { l.c = n.base }
        }
        if [l.t, l.b, l.c, l.d].contains(where: isLetter) { l.kind = .quadLarge }
        return l
    }

    // MARK: Keys

    static let pitch: CGFloat = 64, rowPitch: CGFloat = 62, gap: CGFloat = 6, keyHeight: CGFloat = 56
    /// The key area: 14.5u by six rows.
    static let area = CGSize(width: 14.5 * pitch - gap, height: 5 * rowPitch + keyHeight)

    private typealias Key = KeyHintKeyboard.Key
    private typealias Item = (code: UInt16?, u: CGFloat, kind: Key.Kind)

    /// Every key, left to right and top to bottom, so a left modifier comes before its right twin.
    static func build(shape: Shape, light: Bool, english: Bool, legends: [UInt16: KeyHintKeyboard.Legend], koreanCaps: Bool = false) -> [KeyHintKeyboard.Key] {
        let U = pitch, V = rowPitch, KH = keyHeight
        func kw(_ u: CGFloat) -> CGFloat { u * U - gap }
        var out: [Key] = []
        @discardableResult func row(_ r: Int, _ items: [Item]) -> CGFloat {
            var x: CGFloat = 0
            for it in items {
                out.append(Key(code: it.code, frame: CGRect(x: x, y: CGFloat(r) * V, width: kw(it.u), height: KH), kind: it.kind))
                x += it.u * U
            }
            return x
        }
        // Light keycaps (Neo, Magic Keyboard) never print words on these; US dark ones do.
        let words = english && !light
        func word(_ code: UInt16, _ u: CGFloat, _ trailing: Bool, _ w: String, _ symbol: String, caps: Bool = false) -> Item {
            (code, u, .word(words ? w : symbol, symbol: !words, trailing: trailing, caps: caps))
        }
        func caps(_ u: CGFloat) -> Item {
            koreanCaps ? (57, u, .word("한/A", symbol: false, trailing: false, caps: true)) : word(57, u, false, "caps lock", "⇪", caps: true)
        }
        func mod(_ code: UInt16, _ u: CGFloat, _ symbol: String, _ w: String, left: Bool) -> Item {
            // Dark keyboards print the symbol in the outer top corner, light ones in the inner one.
            (code, u, .modifier(symbol, word: english ? w : nil, symbolTrailing: left != light))
        }
        func chars(_ codes: [UInt16]) -> [Item] { codes.map { ($0, 1, .typing(legends[$0] ?? .init(t: ""))) } }

        let fCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        row(0, [(53, 1.5, .word("esc", symbol: false, trailing: false, caps: false))]
            + (0..<12).map { (fCodes[$0], 1, .function($0 + 1)) } + [(nil, 1, .touchID)])

        switch shape {
        case .ansi:
            row(1, chars([50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]) + [word(51, 1.5, true, "delete", "⌫")])
            row(2, [word(48, 1.5, false, "tab", "⇥")] + chars([12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42]))
            row(3, [caps(1.75)] + chars([0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39])
                + [word(36, 1.75, true, "return", "↵")])
            row(4, [word(56, 2.25, false, "shift", "⇧")] + chars([6, 7, 8, 9, 11, 45, 46, 43, 47, 44]) + [word(60, 2.25, true, "shift", "⇧")])
        case .iso:
            row(1, chars([10, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]) + [word(51, 1.5, true, "delete", "⌫")])
            let x = row(2, [word(48, 1.25, false, "tab", "⇥")] + chars([12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30]))
            var ret = Key(code: 36, frame: CGRect(x: x, y: 2 * V, width: kw(1.25), height: KH + V), kind: word(36, 1.25, true, "return", "↵").kind)
            ret.lShape = Key.LShape(top: kw(1.25), bottom: kw(1), joint: KH)
            out.append(ret)
            row(3, [caps(1.5)] + chars([0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 42]))
            row(4, [word(56, 1.25, false, "shift", "⇧")] + chars([50, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44]) + [word(60, 2.25, true, "shift", "⇧")])
        case .jis:
            // JIS keyboards print the same Latin and kana legends whatever the input source.
            func j(_ code: UInt16, _ t: String, _ b: String, _ kana: String, _ small: String = "", u: CGFloat = 1) -> Item {
                (code, u, .jis(.init(t: t, b: b, c: kana, d: small)))
            }
            func jl(_ code: UInt16, _ kana: String, _ small: String = "") -> Item {
                (code, 1, .jisLetter(.init(t: letters[code] ?? "", c: kana, d: small)))
            }
            row(1, [j(18, "!", "1", "ぬ", u: 1.25), j(19, "\"", "2", "ふ"), j(20, "#", "3", "あ", "ぁ"), j(21, "$", "4", "う", "ぅ"),
                    j(23, "%", "5", "え", "ぇ"), j(22, "&", "6", "お", "ぉ"), j(26, "'", "7", "や", "ゃ"), j(28, "(", "8", "ゆ", "ゅ"),
                    j(25, ")", "9", "よ", "ょ"), j(29, "", "0", "わ", "を"), j(27, "=", "-", "ほ"), j(24, "~", "^", "へ"),
                    j(93, "|", "¥", "ー"), word(51, 1.25, true, "delete", "⌫")])
            row(2, [word(48, 1, false, "tab", "⇥"), jl(12, "た"), jl(13, "て"), jl(14, "い", "ぃ"), jl(15, "す"), jl(17, "か"),
                    jl(16, "ん"), jl(32, "な"), jl(34, "に"), jl(31, "ら"), jl(35, "せ"), j(33, "`", "@", "゛"), j(30, "{", "[", "゜", "「")])
            var ret = Key(code: 36, frame: CGRect(x: 13 * U, y: 2 * V, width: kw(1.5), height: KH + V), kind: word(36, 1.5, true, "return", "↵").kind)
            ret.lShape = Key.LShape(top: kw(1.5), bottom: kw(1.25), joint: KH)
            out.append(ret)
            row(3, [(59, 1.25, .modifier("⌃", word: english ? "control" : nil, symbolTrailing: false)),
                    jl(0, "ち"), jl(1, "と"), jl(2, "し"), jl(3, "は"), jl(5, "き"), jl(4, "く"), jl(38, "ま"), jl(40, "の"), jl(37, "り"),
                    j(41, "+", ";", "れ"), j(39, "*", ":", "け"), j(42, "}", "]", "む", "」")])
            row(4, [word(56, 1.75, false, "shift", "⇧"), jl(6, "つ", "っ"), jl(7, "さ"), jl(8, "そ"), jl(9, "ひ"), jl(11, "こ"),
                    jl(45, "み"), jl(46, "も"), j(43, "<", ",", "ね", "、"), j(47, ">", ".", "る", "。"), j(44, "?", "/", "め", "・"),
                    j(94, "_", "", "ろ"), word(60, 1.75, true, "shift", "⇧")])
        }

        let ax = shape == .jis
            ? row(5, [(57, 1, .jisCaps), mod(58, 1, "⌥", "option", left: true), mod(55, 1.25, "⌘", "command", left: true),
                      (102, 1.25, .jisCenter("英数")), (49, 3.5, .space), (104, 1.25, .jisCenter("かな")),
                      mod(54, 1.25, "⌘", "command", left: false), (nil, 1, .fn(.jis))])
            : row(5, [(nil, 1, .fn(light ? .neo : .standard)), mod(59, 1, "⌃", "control", left: true), mod(58, 1, "⌥", "option", left: true),
                      mod(55, 1.25, "⌘", "command", left: true), (49, 5, .space),
                      mod(54, 1.25, "⌘", "command", left: false), mod(61, 1, "⌥", "option", left: false)])
        // The inverted T: half-height keys, up and down sharing one slot.
        let ah = (KH - 4) / 2, y5 = 5 * V
        let arrows: [(code: UInt16, dx: CGFloat, top: Bool, dir: Key.Direction)] = [(123, 0, false, .left), (126, 1, true, .up),
                                                                                  (125, 1, false, .down), (124, 2, false, .right)]
        for (code, dx, top, dir) in arrows {
            out.append(Key(code: code, frame: CGRect(x: ax + dx * U, y: top ? y5 : y5 + ah + 4, width: kw(1), height: ah),
                           kind: .arrow(dir)))
        }

        for i in out.indices {
            switch out[i].code {
            case 56, 60: out[i].modifier = .shift
            case 59: out[i].modifier = .control
            case 58, 61: out[i].modifier = .option
            case 55, 54: out[i].modifier = .command
            case 3, 38: out[i].home = true
            default: break
            }
        }
        return out
    }
}

// MARK: - Finishes

extension MacKeyboard {
    /// A model in one colour: the deck the keys sit in, its edge highlight and, for light keycaps, the
    /// key face and legend colours.
    struct Finish: Equatable {
        let name: String
        let family: Family
        let dark: Bool
        /// Top and bottom of the deck's gradient.
        let deck: (UInt32, UInt32)
        let edge: UInt32
        let edgeAlpha: CGFloat
        var keyFace: UInt32? = nil
        var keyLegend: UInt32? = nil

        var lightKeys: Bool { keyFace != nil }
        /// "Space Black" from "MacBook Pro · Space Black".
        var colour: String { name.components(separatedBy: " · ").last ?? name }
        /// `macbook-pro-space-black`, as written in the config.
        var slug: String { MacKeyboard.slug(name) }

        static func == (a: Finish, b: Finish) -> Bool { a.name == b.name }

        static let all: [Finish] = [
            Finish(name: "MacBook Pro · Space Black", family: .pro, dark: true, deck: (0x4A484B, 0x2D2B2E), edge: 0xFFFFFF, edgeAlpha: 0.13),
            Finish(name: "MacBook Pro · Silver", family: .pro, dark: false, deck: (0xDFDFE1, 0xE5E6E8), edge: 0xFFFFFF, edgeAlpha: 0.95),
            Finish(name: "MacBook Air · Midnight", family: .air, dark: true, deck: (0x48505C, 0x535B68), edge: 0xE1E8F5, edgeAlpha: 0.22),
            Finish(name: "MacBook Air · Starlight", family: .air, dark: false, deck: (0xE8E1D7, 0xEEE7DD), edge: 0xFFFDF8, edgeAlpha: 0.95),
            Finish(name: "MacBook Air · Sky Blue", family: .air, dark: false, deck: (0xCDD8DE, 0xD5E0E6), edge: 0xFAFDFF, edgeAlpha: 0.95),
            Finish(name: "MacBook Air · Silver", family: .air, dark: false, deck: (0xDADBDD, 0xE2E3E5), edge: 0xFFFFFF, edgeAlpha: 0.95),
            Finish(name: "MacBook Neo · Silver", family: .neo, dark: false, deck: (0xDCDDE0, 0xE2E3E5), edge: 0xFFFFFF, edgeAlpha: 0.95,
                   keyFace: 0xEAEBED, keyLegend: 0x434446),
            Finish(name: "MacBook Neo · Blush", family: .neo, dark: false, deck: (0xE9D0D0, 0xEDD5D5), edge: 0xFFF8F8, edgeAlpha: 0.95,
                   keyFace: 0xF1DFDF, keyLegend: 0x4D4845),
            Finish(name: "MacBook Neo · Citrus", family: .neo, dark: false, deck: (0xE7E593, 0xEDEB98), edge: 0xFFFFEB, edgeAlpha: 0.9,
                   keyFace: 0xF4F3BC, keyLegend: 0x47414B),
            Finish(name: "MacBook Neo · Indigo", family: .neo, dark: true, deck: (0x4F5A70, 0x59647A), edge: 0xDCE4FA, edgeAlpha: 0.2,
                   keyFace: 0x8E99B7, keyLegend: 0x2C3232),
            Finish(name: "iMac · Silver", family: .mk, dark: false, deck: (0xE1E2E4, 0xD4D5D9), edge: 0xFFFFFF, edgeAlpha: 0.9,
                   keyFace: 0xF6F7F9, keyLegend: 0x4A4A4C),
            Finish(name: "iMac · Blue", family: .mk, dark: false, deck: (0xD8E0EB, 0xC7D2E2), edge: 0xFFFFFF, edgeAlpha: 0.9,
                   keyFace: 0xF6F7F9, keyLegend: 0x4A4A4C),
            Finish(name: "iMac · Purple", family: .mk, dark: false, deck: (0xDFDCE9, 0xD1CDE0), edge: 0xFFFFFF, edgeAlpha: 0.9,
                   keyFace: 0xF6F7F9, keyLegend: 0x4A4A4C),
            Finish(name: "iMac · Pink", family: .mk, dark: false, deck: (0xF0D8DE, 0xEAC7D0), edge: 0xFFFFFF, edgeAlpha: 0.9,
                   keyFace: 0xF6F7F9, keyLegend: 0x4A4A4C),
            Finish(name: "iMac · Orange", family: .mk, dark: false, deck: (0xF1DCD3, 0xEBCDC0), edge: 0xFFFFFF, edgeAlpha: 0.9,
                   keyFace: 0xF6F7F9, keyLegend: 0x4A4A4C),
            Finish(name: "iMac · Yellow", family: .mk, dark: false, deck: (0xECE4CE, 0xE4D9B9), edge: 0xFFFFFF, edgeAlpha: 0.9,
                   keyFace: 0xF6F7F9, keyLegend: 0x4A4A4C),
            Finish(name: "iMac · Green", family: .mk, dark: false, deck: (0xD6E3DB, 0xC4D7CC), edge: 0xFFFFFF, edgeAlpha: 0.9,
                   keyFace: 0xF6F7F9, keyLegend: 0x4A4A4C),
        ]

        /// Without a known housing colour: the dark finish in Dark Mode, silver in Light Mode.
        static func automatic(_ family: Family, dark: Bool) -> Finish {
            let name: String
            switch family {
            case .pro: name = dark ? "MacBook Pro · Space Black" : "MacBook Pro · Silver"
            case .air: name = dark ? "MacBook Air · Midnight" : "MacBook Air · Silver"
            case .neo: name = dark ? "MacBook Neo · Indigo" : "MacBook Neo · Silver"
            case .mk: name = "iMac · Silver"
            }
            return all.first { $0.name == name } ?? all[0]
        }
    }
}
