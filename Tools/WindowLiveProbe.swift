import AppKit
import QuartzCore
import ScreenCaptureKit

#if CATWM_RESIZE_PROBE
enum Instance {
    static let scope: ProbeScope? = nil
    static let embedding = ProbeEmbedding()
}
struct ProbeEmbedding { let scope: ProbeScope? = nil }
struct ProbeScope { func filter(_ screens: [Screen]) -> [Screen] { screens } }
extension NSScreen {
    var displayID: CGDirectDisplayID? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
    var displayUUID: String? { nil }
}
#endif

enum LiveProbeError: Error { case missingWindow, timeout, pixels(String) }

@main struct WindowLiveProbe {
    final class Preview: NSView { override var isFlipped: Bool { true } }

    final class Pattern: NSView {
        var updated = false
        override func draw(_: NSRect) {
            for y in stride(from: CGFloat(0), to: bounds.height, by: 8) {
                for x in stride(from: CGFloat(0), to: bounds.width, by: 8) {
                    (Int(x / 8 + y / 8).isMultiple(of: 2) ? NSColor.white : .black).setFill()
                    CGRect(x: x, y: y, width: 8, height: 8).fill()
                }
            }
            (updated ? NSColor.blue : .red).setFill()
            CGRect(x: 40, y: 40, width: 40, height: 40).fill()
        }
    }

    static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(CommandLine.arguments.contains("--tile-fixture") ? .regular : .accessory)
        if CommandLine.arguments.contains("--child") { child(app); return }
        Task { @MainActor in
            do { try await run() } catch { fputs("live probe: \(error)\n", stderr); exit(1) }
            app.terminate(nil)
        }
        app.run()
    }

    static func child(_ app: NSApplication) {
        let tiling = CommandLine.arguments.contains("--tile-fixture")
        if tiling && CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1 {
            exit(77)
        }
        let window = NSWindow(contentRect: CGRect(x: 40, y: 100, width: 600, height: 400),
                              styleMask: tiling ? [.titled, .closable, .resizable] : [.borderless],
                              backing: .buffered, defer: false)
        let pattern = Pattern(frame: window.contentView?.bounds ?? .zero)
        window.contentView = pattern
        window.title = "CatWM disposable live probe"
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isOpaque = true
        window.animationBehavior = .none
        signal(SIGUSR1, SIG_IGN)
        let updates = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        updates.setEventHandler {
            pattern.updated = true
            let frame = window.frame
            window.setFrame(CGRect(x: frame.minX, y: frame.maxY - 450, width: 750, height: 450), display: true)
            pattern.needsDisplay = true
            window.displayIfNeeded()
            CATransaction.flush()
        }
        updates.resume()
        var second: NSWindow?
        if tiling {
            let extra = NSWindow(contentRect: CGRect(x: 680, y: 100, width: 600, height: 400),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            extra.title = "CatWM disposable live probe 2"
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                extra.standardWindowButton(button)?.isHidden = true
            }
            extra.contentView = Pattern(frame: extra.contentView?.bounds ?? .zero)
            extra.orderFrontRegardless()
            second = extra
            app.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            print("\(getpid()) \(window.windowNumber) \(extra.windowNumber)")
        } else {
            window.orderBack(nil)
            print(window.windowNumber)
        }
        window.displayIfNeeded()
        withExtendedLifetime((window, updates, second)) { app.run() }
    }

    @MainActor static func next() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { continuation.resume() }
        }
    }

    @MainActor static func run() async throws {
        let child = Process(), pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.arguments = ["--child"]
        child.standardOutput = pipe
        try child.run()
        let watchdog = DispatchWorkItem {
            kill(child.processIdentifier, SIGCONT)
            if child.isRunning { child.terminate() }
            fputs("live probe: timed out; disposable client stopped\n", stderr)
            exit(1)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: watchdog)
        defer {
            watchdog.cancel()
            kill(child.processIdentifier, SIGCONT)
            if child.isRunning { child.terminate(); child.waitUntilExit() }
        }
        let line = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let id = CGWindowID(line), let screen = NSScreen.screens.first else {
            throw LiveProbeError.missingWindow
        }
        guard CGPreflightScreenCaptureAccess() else { throw NativeWindowStream.Failure.permission }
        var found: SCWindow?
        let deadline = CACurrentMediaTime() + 3
        repeat {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            found = content.windows.first { $0.windowID == id }
            if found == nil { await next() }
        } while found == nil && CACurrentMediaTime() < deadline
        guard let window = found else { throw LiveProbeError.pixels("fixture \(id) absent from shareable windows") }
        let stream = NativeWindowStream()
        try await stream.start(window: window, capacity: CGSize(width: 1000, height: 700), rate: 120)
        do {
            try await check(stream, source: id, child: child, screen: screen)
            await stream.stop()
            print("stream_stopped true; client removed on exit")
        } catch {
            await stream.stop()
            throw error
        }
    }

    @MainActor static func check(_ stream: NativeWindowStream, source: CGWindowID,
                                 child: Process, screen: NSScreen) async throws {
        let end = CACurrentMediaTime() + 6
        while stream.frame == nil, CACurrentMediaTime() < end { await next() }
        guard let first = stream.frame else { throw LiveProbeError.timeout }
        print("native_buffer size \(first.geometry.size) scale \(first.geometry.scale)")
        let panel = CatWMPanel(role: .overlay(.normal, clickThrough: true),
                               frame: CGRect(x: 680, y: 100, width: 850, height: 550))
        let root = CALayer()
        root.isGeometryFlipped = true
        root.backgroundColor = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let view = Preview(frame: CGRect(origin: .zero, size: panel.frame.size))
        view.layer = root
        view.wantsLayer = true
        panel.contentView = view
        let canvas = NativeWindowBufferLayer()
        root.addSublayer(canvas.layer)
        canvas.viewport(CGRect(x: 0, y: 0, width: 700, height: 500))
        canvas.present(first)
        panel.orderBack(nil)
        panel.displayIfNeeded()
        defer { canvas.close(); panel.close() }
        await next()
        canvas.present(first)
        CATransaction.flush()
        await next()
        try compare(source: source, preview: CGWindowID(panel.windowNumber), size: first.geometry.size)
        guard kill(child.processIdentifier, SIGSTOP) == 0 else { throw LiveProbeError.missingWindow }
        for size in [CGSize(width: 380, height: 300), CGSize(width: 800, height: 520)] {
            await withCheckedContinuation { continuation in
                canvas.animate(to: CGRect(origin: .zero, size: size), on: screen, duration: 0.4) {
                    continuation.resume()
                }
            }
            await next()
            try compare(source: source, preview: CGWindowID(panel.windowNumber), size: CGSize(
                width: min(size.width, first.geometry.size.width),
                height: min(size.height, first.geometry.size.height)))
            print("viewport \(canvas.layer.frame)")
            try outside(preview: CGWindowID(panel.windowNumber), size: size)
        }
        print("native_pixels_unstretched true; animated_crop true; outside_bounds_unchanged true")
        try await freshContent(stream, source: source, child: child, canvas: canvas, panel: panel)
    }

    @MainActor static func freshContent(_ stream: NativeWindowStream, source: CGWindowID, child: Process,
                                        canvas: NativeWindowBufferLayer, panel: CatWMPanel) async throws {
        kill(child.processIdentifier, SIGCONT)
        let count = stream.frameCount
        kill(child.processIdentifier, SIGUSR1)
        let deadline = CACurrentMediaTime() + 6
        var fresh = false
        repeat {
            await next()
            if let frame = stream.frame { canvas.present(frame) }
            CATransaction.flush()
            if stream.frameCount > count, let frame = stream.frame, frame.geometry.size.width >= 749 {
                let image = try bitmap(CGWindowID(panel.windowNumber))
                let scale = CGFloat(image.pixelsWide) / panel.frame.width
                if let color = image.colorAt(x: Int(60 * scale), y: Int((frame.geometry.size.height - 60) * scale))?
                    .usingColorSpace(.deviceRGB), color.blueComponent > 0.9 && color.redComponent < 0.1 {
                    fresh = true
                    try compare(source: source, preview: CGWindowID(panel.windowNumber), size: frame.geometry.size)
                    break
                }
            }
        } while CACurrentMediaTime() < deadline
        guard fresh else {
            throw LiveProbeError.pixels("fresh blue client content did not reach the persistent stream")
        }
        print("resized_client_content_live true; one_stream_for_entire_run true; frames \(stream.frameCount)")
    }

    static func bitmap(_ id: CGWindowID) throws -> NSBitmapImageRep {
        guard let shot = WindowSceneCapture.windowImage(id) else { throw LiveProbeError.missingWindow }
        let bitmap = NSBitmapImageRep(cgImage: shot.image)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try data.write(to: URL(fileURLWithPath: "/tmp/catwm-live-\(id).png"))
        }
        return bitmap
    }

    static func compare(source: CGWindowID, preview: CGWindowID, size: CGSize) throws {
        let original = try bitmap(source), rendered = try bitmap(preview)
        let sourceScale = CGFloat(original.pixelsWide) / (WindowSceneCapture.currentFrame(source)?.width ?? 1)
        let targetScale = CGFloat(rendered.pixelsWide) / 850
        for y in stride(from: CGFloat(11), to: size.height - 10, by: 17) {
            for x in stride(from: CGFloat(11), to: size.width - 10, by: 17) {
                guard let expected = original.colorAt(x: Int(x * sourceScale), y: Int(y * sourceScale))?
                    .usingColorSpace(.deviceRGB),
                      let actual = rendered.colorAt(x: Int(x * targetScale), y: Int(y * targetScale))?
                    .usingColorSpace(.deviceRGB),
                      abs(expected.redComponent - actual.redComponent) < 0.04,
                      abs(expected.greenComponent - actual.greenComponent) < 0.04,
                      abs(expected.blueComponent - actual.blueComponent) < 0.04 else {
                    throw LiveProbeError.pixels("native checkerboard changed at \(x),\(y)")
                }
            }
        }
    }

    static func outside(preview: CGWindowID, size: CGSize) throws {
        let image = try bitmap(preview)
        let scale = CGFloat(image.pixelsWide) / 850
        guard let reference = image.colorAt(x: image.pixelsWide - 1, y: image.pixelsHigh - 1)?
            .usingColorSpace(.deviceRGB), reference.greenComponent > 0.9 else {
            throw LiveProbeError.pixels("missing green backdrop control")
        }
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide where CGFloat(x) >= size.width * scale || CGFloat(y) >= size.height * scale {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      abs(color.greenComponent - reference.greenComponent) < 0.01,
                      abs(color.redComponent - reference.redComponent) < 0.01,
                      abs(color.blueComponent - reference.blueComponent) < 0.01 else {
                    let sample = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                    throw LiveProbeError.pixels("crop pixel \(x),\(y): \(String(describing: sample))")
                }
            }
        }
    }
}
