import AppKit

final class FocusSinkWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
