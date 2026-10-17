import AppKit
import SwiftUI

final class SortPanel: NSObject, NSWindowDelegate {

    static let shared = SortPanel()

    let wm = WindowManager.shared
    let model = SortModel()
    var panel: OuchPanel?
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

    var toast: OuchPanel?
    var toastWork: DispatchWorkItem?

    var isOpen: Bool { active }

}
