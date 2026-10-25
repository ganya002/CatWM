import AppKit
import SwiftUI

class PassThroughView: NSView {
    override func hitTest(_: NSPoint) -> NSView? { nil }
}
