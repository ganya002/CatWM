import AppKit
import SwiftUI

struct OMenuButton<Label: View>: View {
    let items: () -> [MenuItem]
    var minWidth: CGFloat = 0
    var style: OButtonStyle? = nil
    @ViewBuilder var label: Label
    @StateObject private var anchor = ScreenAnchor()
    @StateObject private var open = Flag()

    init(minWidth: CGFloat = 0, style: OButtonStyle? = nil, items: @escaping () -> [MenuItem], @ViewBuilder label: () -> Label) {
        self.items = items
        self.minWidth = minWidth
        self.style = style
        self.label = label()
    }

    var body: some View {
        let button = Button {
            guard !open.on, let r = anchor.screenRect else { return }
            open.on = true
            Popup.shared.menu(items, from: r, minWidth: minWidth) { [open] in open.on = false }
        } label: { label }
        Group {
            if let style { button.buttonStyle(style) } else { button.buttonStyle(.plain) }
        }
        .background(AnchorReader(anchor: anchor))
    }
}
