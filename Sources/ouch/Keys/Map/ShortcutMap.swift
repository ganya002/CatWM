import AppKit
import SwiftUI

struct ShortcutMap: View {

    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @StateObject var model = ShortcutMapModel()

    var modifierToggles: some View {
        OSegmented(title: "Modifiers", options: ShortcutMapModel.modifiers.map { OSegmentOption(value: $0.flag.rawValue, label: $0.name, keys: $0.glyph) },
                   isOn: { model.flags.contains(NSEvent.ModifierFlags(rawValue: $0)) },
                   toggle: { model.toggle(NSEvent.ModifierFlags(rawValue: $0)) })
            .animation(Motion.spring, value: model.flags.rawValue)
    }

    var modeEntry: [String]? {
        guard !model.mode.isEmpty, let a = doc.keyActions(in: "").first(where: {
            $0.row.dispatcher == "submap" && $0.arg.lowercased() == model.mode.lowercased()
        }) else { return nil }
        return ConfigDocument.modifierCaps(a.flags) + [ConfigDocument.capLabel(a.key)]
    }

    struct Entry: Identifiable {
        let row: BindRow
        let codes: [UInt16]
        let group: KeyGroup
        var id: UUID { row.id }
    }

}
