import AppKit
import SwiftUI
import MacKeysCore
import MacKeysUI

struct KeyHintKeyboard: View {
    let binds: [KeyHint]
    var pressed: UInt16?
    var hot: Set<UInt16>
    var scale: CGFloat
    private var tap: ((Key) -> Void)?
    private var hover: ((Key, Bool) -> Void)?
    @ObservedObject private var mac = MacKeyboard.shared
    @Environment(\.keyTile) private var tile

    init(binds: [KeyHint], pressed: UInt16? = nil, hot: Set<UInt16> = [], scale: CGFloat = 1) {
        self.binds = binds
        self.pressed = pressed
        self.hot = hot
        self.scale = scale
    }

    func onKeyTap(_ action: @escaping (Key) -> Void) -> Self { var c = self; c.tap = action; return c }
    func onKeyHover(_ action: @escaping (Key, Bool) -> Void) -> Self { var c = self; c.hover = action; return c }

    var body: some View {
        let bound = Dictionary(binds.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let size = Self.size(scale: scale)
        let deck = mac.deckLayout.deck
        ZStack(alignment: .topLeading) {
            MacKeyboardDeckView(device: mac.device, scale: scale)
                .offset(x: -deck.minX * scale, y: -deck.minY * scale)
            ForEach(mac.keys) { k in
                let r = Self.rect(of: k, scale: scale)
                HintKeyCap(key: k, device: mac.device, scale: scale,
                           hint: k.code.flatMap { bound[$0] }, pressed: k.code != nil && k.code == pressed,
                           hot: k.code.map(hot.contains) ?? false, tap: tap, hover: hover)
                    .frame(width: r.width, height: r.height)
                    .tileItem(tile ?? true, style: tile == nil ? .rise : .tile,
                              spread: CGSize(width: (size.width / 2 - r.midX) * 0.35, height: (size.height / 2 - r.midY) * 0.35))
                    .offset(x: r.minX, y: r.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    static func keycap(_ k: Key, hint: KeyHint?, scale: CGFloat) -> some View {
        HintKeyCap(key: k, device: MacKeyboard.shared.device, scale: scale, hint: hint,
                   pressed: false, hot: false, tap: nil, hover: nil, fades: false)
            .frame(width: k.frame.width * scale, height: k.frame.height * scale)
    }

    static func size(scale: CGFloat) -> CGSize {
        let deck = MacKeyboard.shared.deckLayout.deck
        return CGSize(width: deck.width * scale, height: deck.height * scale)
    }

    static func rect(of k: Key, scale: CGFloat) -> CGRect {
        CGRect(x: k.frame.minX * scale, y: k.frame.minY * scale, width: k.frame.width * scale, height: k.frame.height * scale)
    }

    static func cornerRadius(scale: CGFloat) -> CGFloat { 5 * scale }

    struct Key: Identifiable {
        let cap: KeyCap
        let code: UInt16?
        let frame: CGRect
        let modifier: NSEvent.ModifierFlags
        var id: String { cap.id }
        var isL: Bool { cap.iso != nil }

        init(_ cap: KeyCap, layout: MacDeckLayout) {
            self.cap = cap
            code = Self.codes[cap.id]
            frame = layout.frame(of: cap).offsetBy(dx: -layout.deck.minX, dy: -layout.deck.minY)
            switch cap.id {
            case "ShiftLeft", "ShiftRight": modifier = .shift
            case "ControlLeft", "ControlRight": modifier = .control
            case "AltLeft", "AltRight": modifier = .option
            case "MetaLeft", "MetaRight": modifier = .command
            default: modifier = []
            }
        }

        private static let codes: [String: UInt16] = {
            var out: [String: UInt16] = [:]
            for (code, id) in MacKeyCodes.table where id != "Fn" { out[id] = code }
            return out
        }()
    }

    static var keys: [Key] { MacKeyboard.shared.keys }

    static func key(for code: UInt16) -> Key? { keys.first { $0.code == code } }

    static func legend(_ k: Key) -> String {
        switch k.cap.kind {
        case .char, .dual, .quad, .jis, .kana:
            let slots = k.cap.legends
            return (slots.first { $0.slot == .b } ?? slots.first)?.text ?? k.cap.label
        case .space: return "Space"
        case .touchid: return "Touch ID"
        case .fn: return "fn"
        case .fkey: return k.cap.label
        case .mod:
            if k.modifier.contains(.shift) { return "⇧" }
            if k.modifier.contains(.control) { return "⌃" }
            if k.modifier.contains(.option) { return "⌥" }
            return "⌘"
        case .word, .icon, .arrow:
            let named = k.code.flatMap { ConfigDocument.keyName(for: $0) }.map(ConfigDocument.capLabel)
            return named ?? k.cap.legends.first?.text ?? k.cap.label
        }
    }
}
