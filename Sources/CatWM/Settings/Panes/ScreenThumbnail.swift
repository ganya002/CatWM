import AppKit
import SwiftUI

struct ScreenThumbnail: View {
    let layout: Layout

    var body: some View {
        VStack(spacing: 2) {
            LayoutThumbnail(layout: layout, selected: true)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous)
                    .fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous)
                    .strokeBorder(Theme.borderControl, lineWidth: 1.5))
            Capsule().fill(Theme.borderControl).frame(width: 14, height: 2.5)
        }
    }
}
