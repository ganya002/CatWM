import AppKit
import SwiftUI

final class SortHost: CatWMHostingView<SortView> {
    var sizeChanged: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        sizeChanged?()
    }
}
