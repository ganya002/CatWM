import AppKit
import SwiftUI

final class ConfigEditorModel: ObservableObject {
    @Published var name = ""
    @Published var symbol: String?
    @Published var hasColor = false
    @Published var color = HSBA()
    @Published var colorText = ""
    @Published var exportID = ""
    @Published var pickingSymbol = false
    @Published var pickingColor = false

    var colorHex: String? { hasColor ? color.hex : nil }
    func set(color new: HSBA?) {
        hasColor = new != nil
        if let new { color = new; colorText = new.hexRGB }
    }
}
