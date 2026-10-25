import AppKit
import SwiftUI

final class KeyDraft: ObservableObject {
    @Published var dispatcher: String
    @Published var args: String
    @Published var flags: NSEvent.ModifierFlags
    @Published var mode: String
    @Published var search = ""
    @Published var open: MenuCategory?
    let row: BindRow?
    let isRange: Bool

    init(_ action: ConfigDocument.KeyAction?, flags: NSEvent.ModifierFlags, mode: String) {
        row = action?.row
        isRange = action?.isRange ?? false
        dispatcher = action?.row.dispatcher ?? ""
        args = action?.arg ?? ""
        self.flags = flags
        self.mode = mode
    }
}
