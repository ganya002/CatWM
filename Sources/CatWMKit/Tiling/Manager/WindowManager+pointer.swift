import AppKit

extension WindowManager {
    package func mouseLocation() -> CGPoint { backend.pointerLocation() }
}
