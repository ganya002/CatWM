import AppKit
import SwiftUI

final class CursorActions {

    static let shared = CursorActions()

    let model = CursorActionsModel()
    var dotPanel: NSPanel?
    var menuPanel: NSPanel?
    var moveTap: CFMachPort?
    var moveSource: CFRunLoopSource?
    var lastFollow = CGPoint(x: -1, y: -1)
    var shown = false
    var opening = false
    var closeWork: DispatchWorkItem?
    var screenshotTask: Task<Void, Never>?
    static let dotSize = CursorActionsView.markSize

    var enabled: Bool { WindowManager.shared.config.cursorActions }
    var isMenuOpen: Bool { model.open }

}
