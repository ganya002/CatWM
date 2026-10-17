import AppKit
import SwiftUI

extension OSegment where Lead == EmptyView {
    init(label: String, keys: String? = nil, count: Int? = nil, on: Bool, hot: Bool = false, thumb: Namespace.ID? = nil,
         action: @escaping () -> Void) {
        self.init(label: label, keys: keys, count: count, on: on, hot: hot, thumb: thumb, action: action) { _ in EmptyView() }
    }
}
