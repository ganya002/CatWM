import AppKit
import SwiftUI

struct SortToastView: View {
    let text: String
    let keys: [String]
    let undo: () -> Void
    static var inset: EdgeInsets { EdgeInsets(all: Elevation.float.room) }

    var body: some View {
        HStack(spacing: 12) {
            Text(text).font(Theme.body(13.5)).oneLine()
            OButton("Undo", variant: .ghost, shortcut: keys, action: undo)
        }
        .surface(.sm, glass: true)
        .padding(Self.inset)
        .fixedSize()
    }
}
