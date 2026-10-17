import AppKit
import SwiftUI

extension OMenuRow where Lead == EmptyView {
    init(highlighted: Bool? = nil, open: Bool = false, danger: Bool = false, action: @escaping () -> Void,
         @ViewBuilder label: () -> Label, @ViewBuilder trailing: () -> Trailing) {
        self.init(highlighted: highlighted, open: open, danger: danger, action: action, lead: { EmptyView() }, label: label,
                  trailing: trailing)
    }
}
