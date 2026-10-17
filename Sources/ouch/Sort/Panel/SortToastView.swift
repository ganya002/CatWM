import AppKit
import SwiftUI

struct SortToastView: View {
    let text: String
    let keys: [String]
    let undo: () -> Void
    static let inset = EdgeInsets(top: 20, leading: 40, bottom: 56, trailing: 40)

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
