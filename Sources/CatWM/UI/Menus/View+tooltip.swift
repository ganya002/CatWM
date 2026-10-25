import AppKit
import SwiftUI

extension View {
    func tooltip(_ text: String, keys: [String] = []) -> some View {
        background(TooltipReader(text: text, chords: keys.isEmpty ? [] : [keys]))
    }
}
