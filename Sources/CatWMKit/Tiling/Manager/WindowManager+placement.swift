import AppKit

extension WindowManager {
    package func setFloating(_ floating: Bool, for window: Window) {
        guard window.isFloating != floating else { return }
        window.userFloating = .chosen(floating)
        floats.floatZoom[window.id] = nil
        if floating {
            targets[window.id] = nil
        } else {
            if let screen = screen(containing: window.cachedFrame) {
                assignManagedWindow(window.id, to: shown[screen.uuid])
            }
            corrections[window.id] = nil
        }
        refresh()
    }

    package func resizeWindow(_ window: Window, to size: CGSize) {
        guard window.resizable, size.width > 0, size.height > 0 else { return }
        placeFloating(window) { frame, _ in CGRect(origin: frame.origin, size: size) }
    }

    package func moveWindow(_ window: Window, toOffset offset: CGPoint) {
        placeFloating(window) { frame, screen in
            CGRect(origin: CGPoint(x: screen.visible.minX + offset.x, y: screen.visible.minY + offset.y),
                   size: frame.size)
        }
    }

    package func centerWindow(_ window: Window) {
        placeFloating(window) { frame, screen in
            CGRect(x: screen.visible.midX - frame.width / 2, y: screen.visible.midY - frame.height / 2,
                   width: frame.width, height: frame.height)
        }
    }

    private func placeFloating(_ window: Window, _ target: (_ frame: CGRect, _ screen: Screen) -> CGRect) {
        guard floatsFreely(window.id), let screen = screen(of: window) else { return }
        let frame = animator.destination(window.id) ?? window.cachedFrame
        guard !frame.isNull else { return }
        var rect = target(frame, screen)
        rect.origin.x = max(screen.visible.minX, min(rect.minX, screen.visible.maxX - rect.width))
        rect.origin.y = max(screen.visible.minY, min(rect.minY, screen.visible.maxY - rect.height))
        floats.floatZoom[window.id] = nil
        animator.animate([.init(window: window, to: rect.pixelAligned, bounds: screen.visible)],
                         spec: MotionSpec(config))
    }
}
