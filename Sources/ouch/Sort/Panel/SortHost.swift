import AppKit
import SwiftUI

final class SortHost: OuchHostingView<SortView> {
    var sizeChanged: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        sizeChanged?()
    }
}
