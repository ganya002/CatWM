import AppKit
import QuartzCore

package final class WindowResizeScene {
    private final class SceneView: NSView {
        package override var isFlipped: Bool { true }
    }

    private struct Display {
        package let panel: CatWMPanel
        package let frame: CGRect
        package let layers: [CGWindowID: CALayer]
        package let mask: CAShapeLayer
    }
    private var displays: [Display] = []
    private var placements: [CGWindowID: WindowScenePlacement]
    package var onDismiss: (() -> Void)?
    package var onContentsUpdate: ((CGWindowID, CGImage) -> Void)?
    private var dismiss: DismissMonitor?
    private var capturing: Set<CGWindowID> = []
    package private(set) var visible = false
    package let ids: Set<CGWindowID>

    package init(capture: WindowSceneCapture, frames: [CGWindowID: CGRect]) {
        ids = Set(frames.keys)
        placements = frames.mapValues { WindowScenePlacement(frame: $0) }
        for display in capture.displays {
            guard let screen = display.screen.nsScreen else { continue }
            let panel = CatWMPanel(role: .overlay(.normal, clickThrough: true), frame: screen.frame)
            panel.collectionBehavior = [.stationary, .fullScreenAuxiliary, .ignoresCycle]
            let view = SceneView(frame: CGRect(origin: .zero, size: screen.frame.size))
            let root = CALayer()
            root.isGeometryFlipped = true
            let background = CALayer()
            background.contents = display.background
            background.contentsGravity = .resize
            background.frame = view.bounds
            background.isGeometryFlipped = true
            let mask = CAShapeLayer()
            mask.frame = background.bounds
            background.mask = mask
            root.addSublayer(background)
            view.layer = root
            view.wantsLayer = true
            panel.contentView = view
            var layers: [CGWindowID: CALayer] = [:]
            for id in capture.order {
                guard let image = capture.images[id], let frame = frames[id] else { continue }
                let layer = CALayer()
                layer.contents = image
                layer.contentsGravity = .resize
                layer.masksToBounds = true
                layer.frame = frame.offsetBy(dx: -display.screen.frame.minX, dy: -display.screen.frame.minY)
                root.addSublayer(layer)
                layers[id] = layer
            }
            displays.append(Display(panel: panel, frame: display.screen.frame, layers: layers, mask: mask))
        }
        updateMasks()
    }

    package func cover(_ id: CGWindowID, to target: CGRect) {
        placements[id]?.retarget(to: target)
        updateMasks()
    }

    package func placed(_ id: CGWindowID, at target: CGRect) {
        guard let actual = WindowSceneCapture.currentFrame(id) else { return }
        placements[id]?.landed(at: actual, target: target)
        updateMasks()
    }

    private func updateMasks() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for display in displays {
            let path = CGMutablePath()
            for placement in placements.values {
                let local = placement.coverage.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                path.addRect(CGRect(x: local.minX, y: display.frame.height - local.maxY,
                                    width: local.width, height: local.height))
            }
            display.mask.path = path
        }
        CATransaction.commit()
    }

    package func contains(_ frame: CGRect) -> Bool {
        let regions = placements.values.map { $0.requested.union(frame) }
        let participants = ids.union(displays.map { CGWindowID($0.panel.windowNumber) })
        return displays.contains { $0.frame.contains(frame) }
            && WindowSceneCapture.canPresent(regions, participants: participants)
    }

    package func show() {
        guard !visible else { return }
        visible = true
        for display in displays { display.panel.orderFrontRegardless(); display.panel.displayIfNeeded() }
        CATransaction.flush()
        let dismiss = DismissMonitor()
        dismiss.start(keeps: { _ in false }, screens: true, close: { [weak self] in self?.dismissed() })
        self.dismiss = dismiss
    }

    package func update(_ frames: [CGWindowID: CGRect]) {
        guard visible else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for display in displays {
            for (id, frame) in frames {
                display.layers[id]?.frame = frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            }
        }
        CATransaction.commit()
        refreshContents()
    }

    private func refreshContents() {
        for id in ids where capturing.insert(id).inserted {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                let snapshot = WindowSceneCapture.windowImage(id)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.capturing.remove(id)
                    guard self.visible, let snapshot else { return }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    for display in self.displays { display.layers[id]?.contents = snapshot.image }
                    if let target = self.placements[id]?.requested {
                        self.placements[id]?.landed(at: snapshot.frame, target: target)
                    }
                    self.updateMasks()
                    CATransaction.commit()
                    self.onContentsUpdate?(id, snapshot.image)
                }
            }
        }
    }

    private func dismissed() {
        let callback = onDismiss
        close()
        callback?()
    }

    package func close() {
        visible = false
        onDismiss = nil
        onContentsUpdate = nil
        dismiss?.stop(); dismiss = nil
        for display in displays { display.panel.orderOut(nil); display.panel.close() }
        displays.removeAll()
    }

    deinit { close() }
}
