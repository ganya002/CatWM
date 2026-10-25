import AppKit
import SwiftUI

final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
    override func mouseDown(with _: NSEvent) { onClick?() }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}
