import AppKit
import SwiftUI

struct ShortcutMap: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settings: SettingsUI
    @StateObject var model = ShortcutMapModel()

    var modeEntry: [String]? {
        guard !model.mode.isEmpty, let action = doc.keyActions(in: "").first(where: {
            $0.row.dispatcher == "submap" && $0.arg.lowercased() == model.mode.lowercased()
        }) else { return nil }
        return ConfigDocument.modifierCaps(action.flags) + [ConfigDocument.capLabel(action.key)]
    }

    struct Entry: Identifiable {
        let row: BindRow
        let codes: [UInt16]
        let group: KeyGroup
        var id: UUID { row.id }
    }
}
