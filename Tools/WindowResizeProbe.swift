import AppKit
@preconcurrency import ApplicationServices
import QuartzCore

#if CATWM_RESIZE_PROBE
enum Instance { static let scope: ProbeScope? = nil }
struct ProbeScope { func filter(_ screens: [Screen]) -> [Screen] { screens } }
extension NSScreen {
    var displayID: CGDirectDisplayID? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
    var displayUUID: String? { nil }
}
#endif

enum ResizeProbeError: Error {
    case missingWindow, captureUnavailable, pixelMismatch, writeFailed, displayStopped
}

@main struct WindowResizeProbe {
    final class Pattern: NSView {
        var updated = false
        override func draw(_: NSRect) {
            let colors: [NSColor] = [updated ? .magenta : .systemRed, .systemGreen, .systemBlue, .systemOrange]
            for (index, color) in colors.enumerated() {
                color.setFill()
                CGRect(x: CGFloat(index) * bounds.width / 4, y: 0,
                       width: bounds.width / 4, height: bounds.height).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 24), .foregroundColor: NSColor.white
            ]
            "CatWM resize proxy".draw(at: CGPoint(x: 20, y: 30), withAttributes: attributes)
        }
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--child") { child(app); return }
        Task { @MainActor in
            do { try await run() } catch { fputs("resize probe: \(error)\n", stderr); exit(1) }
            app.terminate(nil)
        }
        app.run()
    }

    static func child(_ app: NSApplication) {
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 480, height: 320),
                              styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.title = "CatWM disposable resize probe"
        window.animationBehavior = .none
        let pattern = Pattern(frame: window.contentView?.bounds ?? .zero)
        window.contentView = pattern
        signal(SIGUSR1, SIG_IGN)
        let updates = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        updates.setEventHandler {
            pattern.updated = true
            pattern.needsDisplay = true
            window.displayIfNeeded()
            CATransaction.flush()
        }
        updates.resume()
        window.orderFrontRegardless()
        print(window.windowNumber); fflush(stdout)
        withExtendedLifetime((window, updates)) { app.run() }
    }

    static func waitForWindow(_ id: CGWindowID) -> CGRect? {
        let deadline = Date().addingTimeInterval(2)
        repeat {
            if let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first,
               info[kCGWindowIsOnscreen as String] as? Bool == true,
               let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) { return frame }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        } while Date() < deadline
        return nil
    }

    static func checkPixels(frame: CGRect, screen: Screen, path: String, updated: Bool) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let image = NSBitmapImageRep(data: data) else { throw ResizeProbeError.pixelMismatch }
        let scale = CGFloat(image.pixelsWide) / screen.frame.width
        let y = Int(frame.midY * scale)
        let left = Int(frame.minX * scale), right = Int(frame.maxX * scale)
        func color(_ x: Int, _ y: Int) -> NSColor? { image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) }
        guard let red = color(left + 4, y),
              let green = color(Int((frame.minX + frame.width * 0.375) * scale), y),
              let blue = color(Int((frame.minX + frame.width * 0.625) * scale), y),
              let orange = color(right - 4, y), let outside = color(left - 4, y),
              red.redComponent > 0.9, red.greenComponent < 0.4,
              green.greenComponent > 0.6, green.redComponent < 0.4,
              blue.blueComponent > 0.9, blue.redComponent < 0.4,
              orange.redComponent > 0.9, orange.blueComponent < 0.4,
              outside.redComponent < 0.9 else { throw ResizeProbeError.pixelMismatch }
        if updated {
            guard red.blueComponent > 0.8 else { throw ResizeProbeError.pixelMismatch }
            print("resizing_content_live true", path)
        }
        let bottom = Int(frame.maxY * scale)
        guard let insideBottom = color(left + 40, bottom - 4), let outsideBottom = color(left + 40, bottom + 4),
              insideBottom.redComponent > 0.9, outsideBottom.redComponent < 0.9 else {
            throw ResizeProbeError.pixelMismatch
        }
        let top = Int(frame.minY * scale), middle = Int(frame.midX * scale)
        guard let above = color(middle, top - 4), above.redComponent < 0.05,
              above.greenComponent < 0.05, above.blueComponent < 0.05 else { throw ResizeProbeError.pixelMismatch }
        let markerX = Int((screen.frame.maxX - 80) * scale)
        let markerY = Int((screen.frame.minY + 120) * scale)
        guard let live = color(markerX, markerY), live.greenComponent > 0.8, live.redComponent < 0.1 else {
            throw ResizeProbeError.pixelMismatch
        }
        print("pixel_fit true", path)
        print("unrelated_content_live true", path)
    }

    static func makeBackdrop(on screen: Screen, below id: CGWindowID) -> (panel: CatWMPanel, marker: CALayer) {
        let frame = screen.nsScreen?.frame ?? .zero
        let panel = CatWMPanel(role: .overlay(.normal, clickThrough: true), frame: frame)
        panel.backgroundColor = .black
        panel.isOpaque = true
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let marker = CALayer()
        marker.backgroundColor = NSColor.red.cgColor
        marker.frame = CGRect(x: frame.width - 120, y: frame.height - 160, width: 80, height: 80)
        view.layer?.addSublayer(marker)
        panel.contentView = view
        panel.order(.below, relativeTo: Int(id))
        panel.displayIfNeeded()
        CATransaction.flush()
        return (panel, marker)
    }

    @MainActor static func run() async throws {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = ["--child"]
        process.standardOutput = pipe
        try process.run()
        defer {
            kill(process.processIdentifier, SIGCONT)
            if process.isRunning { process.terminate(); process.waitUntilExit() }
        }
        guard let text = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8) else {
            throw ResizeProbeError.missingWindow
        }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = CGWindowID(line), let from = waitForWindow(id),
              let screen = Screen.all().first(where: { $0.frame.contains(from.center) }) else {
            throw ResizeProbeError.missingWindow
        }
        let backdrop = makeBackdrop(on: screen, below: id)
        defer { backdrop.panel.close() }
        print("prewarm", WindowSceneCapture.prepare(window: id))
        let started = CACurrentMediaTime()
        guard let captured = WindowSceneCapture.take(frames: [id: from], screens: [screen]) else {
            throw ResizeProbeError.captureUnavailable
        }
        print("capture_ms \((CACurrentMediaTime() - started) * 1000)")
        let scene = WindowResizeScene(capture: captured, frames: [id: from])
        defer { scene.close() }
        scene.show()
        let target = CGRect(x: screen.frame.minX + 400, y: screen.frame.minY + 100, width: 760, height: 560)
        try await ResizeProbeAnimation(scene: scene, id: id, from: from, target: target,
                                       screen: screen, pid: process.processIdentifier, marker: backdrop.marker).run()
        guard let actual = waitForWindow(id), actual.approxEqual(target, tolerance: 1) else {
            throw ResizeProbeError.writeFailed
        }
        print("live_frame_fit true target \(target)")
    }
}
