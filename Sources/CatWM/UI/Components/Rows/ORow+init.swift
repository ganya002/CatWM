import AppKit
import SwiftUI

extension ORow where Control == EmptyView {
    init(_ label: String, description: String? = nil, symbol: String? = nil) {
        self.init(label, description: description, symbol: symbol) { EmptyView() }
    }
}
