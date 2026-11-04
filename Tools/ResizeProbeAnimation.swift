import AppKit
@preconcurrency import ApplicationServices
import QuartzCore

@MainActor final class ResizeProbeAnimation {
    private let scene: WindowResizeScene
    private let id: CGWindowID
    private let from: CGRect, target: CGRect
    private let screen: Screen
    private let pid: pid_t
    private let marker: CALayer
    private var clock: WindowFrameClock?
    private var continuation: CheckedContinuation<Void, Error>?
    private var resumed = false, saved = false, savedLive = false, landed = false, changedContent = false
    private let started = CACurrentMediaTime()

    init(scene: WindowResizeScene, id: CGWindowID, from: CGRect, target: CGRect,
         screen: Screen, pid: pid_t, marker: CALayer) {
        self.scene = scene; self.id = id; self.from = from; self.target = target
        self.screen = screen; self.pid = pid; self.marker = marker
    }

    func run() async throws {
        guard let nsScreen = screen.nsScreen else { throw ResizeProbeError.displayStopped }
        guard kill(pid, SIGSTOP) == 0 else { throw ResizeProbeError.missingWindow }
        defer { kill(pid, SIGCONT); clock?.stop() }
        scene.cover(id, to: target)
        scene.onContentsUpdate = { [weak self] id, image in self?.received(id, image: image) }
        placeLiveWindow()
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            clock = WindowFrameClock(screen: nsScreen) { [weak self] in self?.tick($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.finish(.failure(ResizeProbeError.displayStopped))
            }
        }
    }

    private func placeLiveWindow() {
        DispatchQueue.global(qos: .userInteractive).async { [pid, target, weak self] in
            let app = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?, size = target.size, point = target.origin
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let element = (value as? [AXUIElement])?.first,
                  let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &point) else {
                DispatchQueue.main.async { self?.finish(.failure(ResizeProbeError.missingWindow)) }
                return
            }
            let errors = [AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue),
                          AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue),
                          AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)]
            DispatchQueue.main.async {
                guard let self else { return }
                guard errors.allSatisfy({ $0 == .success }) else {
                    self.finish(.failure(ResizeProbeError.writeFailed)); return
                }
                self.scene.placed(self.id, at: target)
                self.landed = true
            }
        }
    }

    private func received(_ id: CGWindowID, image: CGImage) {
        guard id == self.id, !changedContent else { return }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let color = bitmap.colorAt(x: image.width / 8, y: image.height / 2)?.usingColorSpace(.deviceRGB) else {
            return
        }
        changedContent = color.redComponent > 0.9 && color.blueComponent > 0.8
    }

    private func tick(_ time: CFTimeInterval) {
        let elapsed = time - started
        let progress = min(1, max(0, elapsed / 2))
        let eased = 1 - pow(1 - progress, 3)
        let frame = CGRect(x: from.minX + (target.minX - from.minX) * eased,
                           y: from.minY + (target.minY - from.minY) * eased,
                           width: from.width + (target.width - from.width) * eased,
                           height: from.height + (target.height - from.height) * eased)
        scene.update([id: frame])
        if elapsed >= 0.1 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            marker.backgroundColor = NSColor.green.cgColor
            CATransaction.commit()
        }
        if elapsed >= 0.3, !saved {
            saved = true
            do { try screenshot(frame, label: "stalled") } catch { finish(.failure(error)); return }
        }
        if elapsed >= 0.55, !resumed { kill(pid, SIGCONT); kill(pid, SIGUSR1); resumed = true }
        if elapsed >= 0.8, landed, changedContent, !savedLive {
            savedLive = true
            do { try screenshot(frame, label: "live") } catch { finish(.failure(error)); return }
        }
        if elapsed >= 2 {
            finish(landed && savedLive ? .success(()) : .failure(ResizeProbeError.writeFailed))
        }
    }

    private func screenshot(_ frame: CGRect, label: String) throws {
        clock?.stop()
        CATransaction.flush()
        print("\(label)_expected_frame \(frame)")
        let shot = Process()
        shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let path = "/tmp/catwm-resize-\(label).png"
        shot.arguments = ["-x", path]
        try shot.run(); shot.waitUntilExit()
        guard shot.terminationStatus == 0 else { throw ResizeProbeError.pixelMismatch }
        try WindowResizeProbe.checkPixels(frame: frame, screen: screen, path: path, updated: label == "live")
        let detail = frame.insetBy(dx: -10, dy: -10).integral
        let region = "\(Int(detail.minX)),\(Int(detail.minY)),\(Int(detail.width)),\(Int(detail.height))"
        let detailShot = Process()
        detailShot.executableURL = shot.executableURL
        detailShot.arguments = ["-x", "-R\(region)", "/tmp/catwm-resize-\(label)-detail.png"]
        try detailShot.run(); detailShot.waitUntilExit()
        guard detailShot.terminationStatus == 0 else { throw ResizeProbeError.pixelMismatch }
        if let nsScreen = screen.nsScreen {
            clock = WindowFrameClock(screen: nsScreen) { [weak self] in self?.tick($0) }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        clock?.stop(); clock = nil
        let waiting = continuation
        continuation = nil
        waiting?.resume(with: result)
    }
}
