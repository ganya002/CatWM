import AppKit
import QuartzCore

@MainActor package final class WindowResizeFill {
    private let panel: CatWMPanel
    private let root = CALayer()
    private let fill = CALayer()
    private let profile = CALayer()
    private let leftProfile = CALayer()
    private let leftTail = CALayer()
    private let bottomProfile = CALayer()
    private let outline = CALayer()
    private let border = CALayer()
    private let gap = CALayer()
    private let outside = CAShapeLayer()
    private let inverse = CALayer()
    private let movingCorners = CAShapeLayer()
    private let appearance: WindowFillAppearance
    private let window: CGWindowID
    private var dismiss: DismissMonitor?
    package var onDismiss: (@MainActor () -> Void)?

    package var windowID: CGWindowID { CGWindowID(panel.windowNumber) }

    package init(window: CGWindowID, appearance: WindowFillAppearance) {
        self.window = window
        self.appearance = appearance
        panel = CatWMPanel(role: .overlay(.normal, clickThrough: true))
        panel.animationBehavior = .none
        panel.collectionBehavior = [.stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: .zero)
        root.masksToBounds = true
        fill.backgroundColor = appearance.rightColor
        leftTail.backgroundColor = appearance.leftColor
        fill.addSublayer(leftTail)
        profile.contents = appearance.rightEdge
        leftProfile.contents = appearance.leftEdge
        bottomProfile.contents = appearance.bottomEdge
        bottomProfile.contentsCenter = appearance.bottomCenter
        for layer in [profile, leftProfile, bottomProfile, outline, inverse, border] {
            layer.contentsGravity = .resize
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
        }
        for layer in [profile, leftProfile, bottomProfile] { fill.addSublayer(layer) }
        outline.contents = appearance.outline
        outline.contentsCenter = appearance.center
        outline.contentsScale = CGFloat(appearance.rightEdge.height) / appearance.sourceSize.height
        for layer in [profile, leftProfile, bottomProfile] { layer.contentsScale = outline.contentsScale }
        border.contents = appearance.border
        border.contentsCenter = appearance.center
        border.contentsScale = outline.contentsScale
        fill.addSublayer(border)
        root.addSublayer(fill)
        root.mask = outline
        fill.mask = gap
        gap.masksToBounds = true
        outside.fillRule = .evenOdd
        gap.addSublayer(outside)
        inverse.contents = appearance.inverseOutline
        inverse.contentsCenter = appearance.center
        inverse.contentsScale = outline.contentsScale
        movingCorners.fillRule = .evenOdd
        inverse.mask = movingCorners
        gap.addSublayer(inverse)
        let canvas = CALayer()
        canvas.addSublayer(root)
        view.layer = canvas
        view.wantsLayer = true
        panel.contentView = view
    }

    package func update(desired: CGRect, actual: CGRect, order: [CGWindowID]? = nil) {
        guard !desired.isNull, !actual.isNull, desired.width > 0, desired.height > 0,
              actual.width > 0, actual.height > 0,
              desired.width >= appearance.minimumSize.width, desired.height >= appearance.minimumSize.height,
              actual.width >= appearance.minimumSize.width, actual.height >= appearance.minimumSize.height,
              desired.minY == actual.minY, desired.intersects(actual),
              let screen = Screen.all().first(where: { $0.frame.contains(desired) && $0.frame.contains(actual) }),
              let native = screen.nsScreen,
              abs(outline.contentsScale - native.backingScaleFactor) < 0.01 else { close(); return }
        if actual.contains(desired) || desired.approxEqual(actual, tolerance: 0.25) { close(); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if panel.frame != native.frame { panel.setFrame(native.frame, display: false) }
        for layer in [root, fill, gap, outside, movingCorners] { layer.contentsScale = native.backingScaleFactor }
        let bounds = CGRect(origin: .zero, size: desired.size)
        root.frame = CGRect(x: desired.minX - screen.frame.minX, y: screen.frame.maxY - desired.maxY,
                            width: desired.width, height: desired.height)
        fill.frame = bounds
        outline.frame = bounds
        border.frame = bounds
        updateProfiles(desired: desired, actual: actual)
        updateMask(desired: desired, actual: actual, bounds: bounds)
        CATransaction.commit()
        let stack = order ?? WindowSceneCapture.windowOrder() ?? []
        let above = stack.firstIndex(of: windowID).flatMap { helper in
            stack.firstIndex(of: window).map { helper < $0 }
        } ?? false
        if !panel.isVisible || !above { panel.order(.above, relativeTo: Int(window)) }
        panel.displayIfNeeded()
        if dismiss == nil {
            let dismiss = DismissMonitor()
            dismiss.start(keeps: { _ in false }, screens: true, close: { [weak self] in
                self?.close()
                self?.onDismiss?()
            })
            self.dismiss = dismiss
        }
    }

    private func updateProfiles(desired: CGRect, actual: CGRect) {
        let cap = CGFloat(appearance.outline.width - 1) / 2 / outline.contentsScale
        let overlap = (ceil(outline.contentsScale) + 2) / outline.contentsScale
        let left = actual.minX - desired.minX
        let top = desired.height - appearance.sourceSize.height
        profile.frame = CGRect(x: 0, y: top, width: desired.width, height: appearance.sourceSize.height)
        leftProfile.frame = CGRect(x: 0, y: top, width: max(0, left + cap + overlap),
                                   height: appearance.sourceSize.height)
        leftTail.frame = CGRect(x: 0, y: 0, width: leftProfile.frame.width, height: desired.height)
        bottomProfile.frame = CGRect(x: left, y: 0, width: actual.width,
                                     height: max(0, desired.maxY - actual.maxY + overlap))
    }

    private func updateMask(desired: CGRect, actual: CGRect, bounds: CGRect) {
        gap.frame = bounds
        outside.frame = bounds
        let pixel = 1 / outline.contentsScale
        let hole = cutout(actual: actual, desired: desired, inset: pixel)
        let outsideHole = cutout(actual: actual, desired: desired, inset: pixel * 2)
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(outsideHole)
        outside.path = path
        inverse.frame = hole
        let corners = CGMutablePath()
        let inverseBounds = CGRect(origin: .zero, size: hole.size)
        corners.addRect(inverseBounds)
        let cap = CGFloat(appearance.outline.width - 1) / 2 / outline.contentsScale
        for (sameX, x) in [(actual.minX == desired.minX, CGFloat(0)),
                           (actual.maxX == desired.maxX, hole.width - cap)] where sameX {
            if actual.minY == desired.minY {
                corners.addRect(CGRect(x: x, y: hole.height - cap, width: cap, height: cap))
            }
            if actual.maxY == desired.maxY {
                corners.addRect(CGRect(x: x, y: 0, width: cap, height: cap))
            }
        }
        movingCorners.frame = inverseBounds
        movingCorners.path = corners
    }

    private func cutout(actual: CGRect, desired: CGRect, inset: CGFloat) -> CGRect {
        var hole = actual.offsetBy(dx: -desired.minX, dy: -desired.minY)
        if desired.minX < actual.minX { hole.origin.x += inset; hole.size.width -= inset }
        if desired.maxX > actual.maxX { hole.size.width -= inset }
        if desired.maxY > actual.maxY { hole.size.height -= inset }
        hole.origin.y = desired.height - hole.maxY
        return hole
    }

    package var visible: Bool { panel.isVisible }

    package func close() {
        dismiss?.stop()
        dismiss = nil
        panel.orderOut(nil)
    }

    deinit {
        let panel = panel, dismiss = dismiss
        DispatchQueue.main.async {
            dismiss?.stop()
            panel.orderOut(nil)
        }
    }
}
