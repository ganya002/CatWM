import AppKit
import SwiftUI

struct SortScreenGlyph: View {
    let display: SortDisplay
    let color: Color

    var body: some View {
        let w = min(24, max(16, (12 * display.aspect).rounded()))
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(color, lineWidth: 1.5).frame(width: w, height: 12) // style-ok: a 12pt drawing of a screen
            Capsule().fill(color).frame(width: display.isLaptop ? w + 5 : 6, height: 1.5)
        }
        .frame(height: 16)
    }
}
