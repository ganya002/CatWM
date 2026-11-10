import AppKit
import CatWMKit
import SwiftUI

final class SortPanel: NSObject, NSWindowDelegate {
    static let shared = SortPanel()

    let manager = WindowManager.shared
    let model = SortModel()
    var panel: CatWMPanel?
    var ghostPanel: CatWMPanel?
    var host: SortHost?
    let dismiss = DismissMonitor()
    var active = false
    var fitQueued = false
    var wasPaused = false
    var width: CGFloat = 0
    var screen: NSScreen?
    var generation = 0
    var liveWork: DispatchWorkItem?
    var pruneTimer: Timer?
    var applyingUntil = Date.distantPast

    var undoWork: DispatchWorkItem?

    var isOpen: Bool { active }
}

final class SortHost: CatWMHostingView<SortView> {
    var sizeChanged: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        sizeChanged?()
    }
}
