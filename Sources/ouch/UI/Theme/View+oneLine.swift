import AppKit
import CoreText
import SwiftUI

extension View {
    func oneLine(_ mode: Text.TruncationMode = .tail) -> some View { lineLimit(1).truncationMode(mode) }

    func kicker(_ color: Color = Theme.inkMuted) -> some View {
        font(Theme.heading(12)).tracking(0.6).textCase(.uppercase).foregroundStyle(color)
    }

    func textStyle(_ style: TextStyle) -> some View { font(style.font).tracking(style.tracking) }
}
