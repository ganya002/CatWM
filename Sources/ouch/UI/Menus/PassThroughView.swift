import AppKit
import SwiftUI

class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
