import AppKit
import SwiftUI

extension OMenuRow where Lead == EmptyView {
    init(highlight: MenuRowHighlight = .followsHover, open: Bool = false, danger: Bool = false,
         action: @escaping () -> Void, @ViewBuilder label: () -> Label, @ViewBuilder trailing: () -> Trailing) {
        self.init(highlight: highlight, open: open, danger: danger, action: action, lead: { EmptyView() },
                  label: label, trailing: trailing)
    }
}
