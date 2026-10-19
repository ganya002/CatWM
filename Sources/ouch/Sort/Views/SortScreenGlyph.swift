import AppKit
import SwiftUI

struct SortScreenGlyph: View {
    let display: SortDisplay
    let color: Color

    var body: some View {
        let width = min(24, max(16, (12 * display.aspect).rounded()))
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous) // style-ok: a 12pt drawing of a screen
                .strokeBorder(color, lineWidth: 1.5).frame(width: width, height: 12)
            Capsule().fill(color).frame(width: display.isLaptop ? width + 5 : 6, height: 1.5)
        }
        .frame(height: 16)
    }
}
