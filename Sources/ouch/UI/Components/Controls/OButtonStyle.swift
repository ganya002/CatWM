import AppKit
import SwiftUI

struct OButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        OButtonBody(configuration: configuration, style: self)
    }

    var height: CGFloat { size == .sm ? 26 : size == .lg ? 36 : Theme.controlHeight }
}
