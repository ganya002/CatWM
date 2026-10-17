import AppKit
import SwiftUI

extension OMenuRow where Trailing == EmptyView {
    init(highlighted: Bool? = nil, open: Bool = false, danger: Bool = false, action: @escaping () -> Void,
         @ViewBuilder lead: () -> Lead, @ViewBuilder label: () -> Label) {
        self.init(highlighted: highlighted, open: open, danger: danger, action: action, lead: lead, label: label) { EmptyView() }
    }
}
