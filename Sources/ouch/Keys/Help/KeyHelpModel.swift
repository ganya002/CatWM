import AppKit
import SwiftUI

final class KeyHelpModel: ObservableObject {
    enum Reason { case hold, toggle, menu }

    @Published var shown = false
    var motion = PanelMotion.current
    @Published var mode = ""
    @Published var reason: Reason = .hold
    @Published var held: NSEvent.ModifierFlags = []
    @Published var pressed: UInt16?
    private(set) var base: NSEvent.ModifierFlags = []
    private(set) var binds: [KeyBinding] = []
    static let keyboardMax: CGFloat = 580
    private(set) var keyboardWidth: CGFloat = keyboardMax

    func load(mode: String, binds all: [KeyBinding], chord: NSEvent.ModifierFlags, reason: Reason, room: CGFloat) {
        self.mode = mode
        self.reason = reason
        binds = all.filter { $0.submap == mode && $0.keyCode < 0x1000 }
        let counts = Dictionary(grouping: binds, by: { KeyHelp.mods($0.mods).subtracting(.shift).rawValue }).mapValues(\.count)
        base = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
            .map { NSEvent.ModifierFlags(rawValue: $0.key) } ?? []
        keyboardWidth = min(Self.keyboardMax, max(440, room))
    }

    var shiftLayer: Bool { held.contains(.shift) }
    var layerMods: NSEvent.ModifierFlags { shiftLayer ? base.union(.shift) : base }

    var hints: [KeyHint] {
        let mods = layerMods
        var seen = Set<UInt16>()
        return binds.filter { KeyHelp.mods($0.mods) == mods && seen.insert($0.keyCode).inserted }.map { KeyHint($0) }
    }

    var hot: Set<UInt16> {
        Set(KeyHintKeyboard.keys.filter { !$0.modifier.isEmpty && held.contains($0.modifier) }.compactMap(\.code))
    }
}
