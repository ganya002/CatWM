import AppKit
import SwiftUI

extension OPageTitle where Trailing == EmptyView {
    init(crumbs: [String]) { self.init(crumbs: crumbs) { EmptyView() } }
}
