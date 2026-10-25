import AppKit
import SwiftUI

extension OMenuRow where Trailing == EmptyView {
    init(highlight: MenuRowHighlight = .followsHover, open: Bool = false, danger: Bool = false,
         action: @escaping () -> Void, @ViewBuilder lead: () -> Lead, @ViewBuilder label: () -> Label) {
        self.init(highlight: highlight, open: open, danger: danger, action: action, lead: lead, label: label) {
            EmptyView()
        }
    }
}
