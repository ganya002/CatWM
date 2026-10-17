import AppKit
import CoreText
import SwiftUI

extension View {
    func oneLine(_ mode: Text.TruncationMode = .tail) -> some View { lineLimit(1).truncationMode(mode) }

    func kicker(_ color: Color = Theme.accentInk) -> some View {
        font(Theme.mono(11, .medium)).tracking(0.88).textCase(.uppercase).foregroundStyle(color)
    }

    func textStyle(_ style: TextStyle) -> some View { font(style.font).tracking(style.tracking) }
}
