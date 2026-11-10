import AppKit
import CatWMKit
import MacKeysCore
import MacKeysUI
import SwiftUI

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

    func onKeyTap(_ action: @escaping (Key) -> Void) -> Self { var copy = self; copy.tap = action; return copy }
    func onKeyHover(_ action: @escaping (Key, Bool) -> Void) -> Self {
        var copy = self
        copy.hover = action
        return copy
    }

    var body: some View {
        let bound = Dictionary(binds.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        let size = Self.size(scale: scale)
        let deck = mac.deckLayout.deck
        ZStack(alignment: .topLeading) {
            MacKeyboardDeckView(device: mac.device, scale: scale)
                .offset(x: -deck.minX * scale, y: -deck.minY * scale)
            ForEach(mac.keys) { key in
                let rect = Self.rect(of: key, scale: scale)
                HintKeyCap(key: key, device: mac.device, scale: scale,
                           hint: key.code.flatMap { bound[$0] }, pressed: key.code != nil && key.code == pressed,
                           hot: key.code.map(hot.contains) ?? false, tap: tap, hover: hover)
                    .frame(width: rect.width, height: rect.height)
                    .tileItem(tile.shown, style: tile.style,
                              spread: CGSize(width: (size.width / 2 - rect.midX) * 0.35,
                                             height: (size.height / 2 - rect.midY) * 0.35))
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    static func keycap(_ key: Key, hint: KeyHint?, scale: CGFloat) -> some View {
        HintKeyCap(key: key, device: MacKeyboard.shared.device, scale: scale, hint: hint,
                   pressed: false, hot: false, tap: nil, hover: nil, fades: false)
            .frame(width: key.frame.width * scale, height: key.frame.height * scale)
    }

    static func size(scale: CGFloat) -> CGSize {
        let deck = MacKeyboard.shared.deckLayout.deck
        return CGSize(width: deck.width * scale, height: deck.height * scale)
    }

    static func rect(of key: Key, scale: CGFloat) -> CGRect {
        CGRect(x: key.frame.minX * scale, y: key.frame.minY * scale,
               width: key.frame.width * scale, height: key.frame.height * scale)
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

    static func legend(_ key: Key) -> String {
        switch key.cap.kind {
        case .char, .dual, .quad, .jis, .kana:
            let slots = key.cap.legends
            return (slots.first { $0.slot == .b } ?? slots.first)?.text ?? key.cap.label
        case .space: return "Space"
        case .touchid: return "Touch ID"
        case .fn: return "fn"
        case .fkey: return key.cap.label
        case .mod:
            if key.modifier.contains(.shift) { return "⇧" }
            if key.modifier.contains(.control) { return "⌃" }
            if key.modifier.contains(.option) { return "⌥" }
            return "⌘"
        case .word, .icon, .arrow:
            let named = key.code.flatMap { ConfigDocument.keyName(for: $0) }.map(ConfigDocument.capLabel)
            return named ?? key.cap.legends.first?.text ?? key.cap.label
        }
    }
}
