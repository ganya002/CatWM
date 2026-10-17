import AppKit
import SwiftUI

func cursorMoveCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        CursorActions.shared.reenableMoveTap()
    } else {
        CursorActions.shared.follow(cgPoint: event.location)
    }
    return Unmanaged.passUnretained(event)
}
