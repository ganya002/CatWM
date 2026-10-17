import AppKit
import SwiftUI

extension OPageTitle where Trailing == EmptyView {
    init(crumbs: [String], title: String) { self.init(crumbs: crumbs, title: title) { EmptyView() } }
}
