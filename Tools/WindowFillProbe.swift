import AppKit
import QuartzCore

#if CATWM_RESIZE_PROBE
enum Instance { static let scope: ProbeScope? = nil }
struct ProbeScope { func filter(_ screens: [Screen]) -> [Screen] { screens } }
extension NSScreen {
    var displayID: CGDirectDisplayID? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
    var displayUUID: String? { nil }
}
#endif

enum FillProbeError: Error { case missingWindow, captureUnavailable, interrupted, pixels(String) }

@main struct WindowFillProbe {
    static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--demo") { WindowFillDemo.run(app); return }
        if CommandLine.arguments.contains("--inspect") {
            FillProbeCapture.inspect(CommandLine.arguments.dropFirst(2))
            return
        }
        if CommandLine.arguments.contains("--child") { FillProbeFixture.run(app) }
        Task { @MainActor in
            do { try await FillProbeRun().start() } catch FillProbeError.interrupted {
                fputs("fill probe interrupted: fixture is covered or offscreen; rerun when visible\n", stderr)
                exit(77)
            } catch { fputs("fill probe: \(error)\n", stderr); exit(1) }
            app.terminate(nil)
        }
        app.run()
    }
}

@MainActor final class FillProbeRun {
    var participant: CGWindowID = 0
    private func nextCheck() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { continuation.resume() }
        }
    }

    func start() async throws {
        let child = Process(), pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.arguments = ["--child"] + CommandLine.arguments.filter {
            ["--light", "--dark", "--background"].contains($0) || $0.hasPrefix("--style=")
        }
        child.standardOutput = pipe
        try child.run()
        let watchdog = watchdog(for: child)
        defer {
            watchdog.cancel()
            kill(child.processIdentifier, SIGCONT)
            if child.isRunning { child.terminate(); child.waitUntilExit() }
        }
        let line = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let id = CGWindowID(line), let screen = NSScreen.screens.first else {
            throw FillProbeError.missingWindow
        }
        let actual = try await windowFrame(id); participant = id
        let desired = CGRect(origin: actual.origin, size: CGSize(width: actual.width + 300,
                                                               height: actual.height + 100))
        let area = actual.union(desired).union(actual.offsetBy(dx: -80, dy: 0)).insetBy(dx: -12, dy: -12)
        let backdrop = FillProbeFixture.makeBackdrop(area, window: id, screen: screen)
        defer { backdrop.close() }
        await nextCheck()
        if FillProbeFixture.style == .translucent { try FillProbeFixture.checkAlpha(id, size: actual.size); return }
        let appearance = try await cachedAppearance(id, size: actual.size)
        print("appearance_cached source \(actual) corner_caps \(appearance.minimumSize)")
        if FillProbeFixture.style != .browser {
            guard kill(child.processIdentifier, SIGSTOP) == 0 else { throw FillProbeError.missingWindow }
        }
        await nextCheck()
        let before = try await stableBackdrop(area, window: id)
        try mismatchedScale(id: id, actual: actual, desired: desired)
        let fill = WindowResizeFill(window: id, appearance: appearance)
        defer { fill.close() }
        fill.update(desired: desired, actual: actual)
        await nextCheck()
        let after = try screenshot(area, label: "after", window: id)
        try verify(before: before, after: after, area: area, actual: actual, desired: desired)
        try await variants(fill, before: before, area: area, actual: actual, window: id)
        fill.close()
        try await verifyClosed(before, area: area, window: id)
        if FillProbeFixture.style == .sidebar {
            try await partialResize(fill, child: child, id: id, desired: desired, reference: (area, before))
        }
        try await landing(fill, child: child, id: id, frames: (actual, desired), area: area)
        print("fill_probe true; child resumed and removed on exit")
    }

    private func watchdog(for child: Process) -> DispatchWorkItem {
        let watchdog = DispatchWorkItem {
            if child.isRunning {
                kill(child.processIdentifier, SIGCONT)
                child.terminate()
            }
            fputs("fill probe: timed out; stopping disposable app\n", stderr)
            exit(1)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: watchdog)
        return watchdog
    }

    private func windowFrame(_ id: CGWindowID) async throws -> CGRect {
        let deadline = CACurrentMediaTime() + 2
        repeat {
            if let observed = WindowSceneCapture.currentFrame(id), !observed.isEmpty, !observed.isNull {
                return observed
            }
            await nextCheck()
        } while CACurrentMediaTime() < deadline
        throw FillProbeError.missingWindow
    }

    private func mismatchedScale(id: CGWindowID, actual: CGRect, desired: CGRect) throws {
        guard let snapshot = WindowSceneCapture.windowImage(id),
              let wrongScale = WindowFillAppearance(image: snapshot.image,
                                                    size: CGSize(width: actual.width * 2,
                                                                 height: actual.height * 2)) else {
            throw FillProbeError.captureUnavailable
        }
        let fill = WindowResizeFill(window: id, appearance: wrongScale)
        defer { fill.close() }
        fill.update(desired: desired, actual: actual)
        guard !fill.visible else { throw FillProbeError.pixels("incompatible capture scale was shown") }
        print("incompatible_capture_scale_hidden true")
    }

    private func cachedAppearance(_ id: CGWindowID, size: CGSize) async throws -> WindowFillAppearance {
        let deadline = CACurrentMediaTime() + 2
        repeat {
            if let snapshot = WindowSceneCapture.windowImage(id),
               let appearance = WindowFillAppearance(image: snapshot.image, size: size) { return appearance }
            await nextCheck()
        } while CACurrentMediaTime() < deadline
        throw FillProbeError.captureUnavailable
    }

    private func stableBackdrop(_ area: CGRect, window id: CGWindowID) async throws -> NSBitmapImageRep {
        var before = try screenshot(area, label: "before", window: id)
        let deadline = CACurrentMediaTime() + 2
        while try color(before, x: 0, y: 0, area: area).greenComponent < 0.7,
              CACurrentMediaTime() < deadline {
            await nextCheck()
            before = try screenshot(area, label: "before", window: id)
        }
        repeat {
            await nextCheck()
            let next = try screenshot(area, label: "before", window: id)
            if try matches(before, next, rect: CGRect(origin: .zero, size: area.size), area: area) { return next }
            before = next
        } while CACurrentMediaTime() < deadline
        throw FillProbeError.pixels("backdrop did not settle")
    }

    private func verifyClosed(_ before: NSBitmapImageRep, area: CGRect, window id: CGWindowID) async throws {
        if FillProbeFixture.style == .browser, CommandLine.arguments.contains("--background") {
            await nextCheck()
            try FillProbeCapture.verifyRemoved()
            print("helper_removed_from_window_server true")
            return
        }
        let deadline = CACurrentMediaTime() + 2
        var closed: NSBitmapImageRep
        repeat {
            await nextCheck()
            closed = try screenshot(area, label: "closed", window: id)
            if try matches(before, closed, rect: CGRect(origin: .zero, size: area.size), area: area) { break }
        } while CACurrentMediaTime() < deadline
        try unchanged(before, closed, rect: CGRect(origin: .zero, size: area.size), area: area,
                      label: "cleanup_leaves_no_fill")
    }

    private func variants(_ fill: WindowResizeFill, before: NSBitmapImageRep, area: CGRect,
                          actual: CGRect, window id: CGWindowID) async throws {
        let cases: [(String, CGRect)] = [
            ("width", CGRect(origin: actual.origin,
                             size: CGSize(width: actual.width + 200, height: actual.height))),
            ("height", CGRect(origin: actual.origin,
                              size: CGSize(width: actual.width, height: actual.height + 100))),
            ("left", CGRect(x: actual.minX - 80, y: actual.minY,
                            width: actual.width + 80, height: actual.height)),
            ("fractional", CGRect(x: actual.minX - 0.5, y: actual.minY,
                                  width: actual.width + 100.5, height: actual.height + 60.5))
        ]
        for (label, desired) in cases {
            fill.update(desired: desired, actual: actual)
            await nextCheck()
            let image = try screenshot(area, label: label, window: id)
            try verifyClipping(before: before, after: image, area: area, actual: actual, desired: desired)
            let local = actual.offsetBy(dx: -area.minX, dy: -area.minY)
            try unchanged(before, image, rect: CGRect(x: local.minX + 8, y: local.minY + 10,
                                                     width: 110, height: 16),
                          area: area, label: "\(label)_traffic_lights_unchanged")
            if FillProbeFixture.style == .sidebar {
                try verifySidebar(before, after: image, label: label, area: area, actual: local)
            }
        }
        fill.update(desired: actual.insetBy(dx: 80, dy: 0), actual: actual)
        guard !fill.visible else { throw FillProbeError.pixels("shrink left stale fill") }
        fill.update(desired: actual.offsetBy(dx: 0, dy: -20), actual: actual)
        guard !fill.visible else { throw FillProbeError.pixels("vertical move repeated the titlebar") }
        print("retarget_shrink_and_unsupported_geometry_dismiss true")
    }

    private func landing(_ fill: WindowResizeFill, child: Process, id: CGWindowID,
                         frames: (actual: CGRect, desired: CGRect),
                         area: CGRect) async throws {
        let desired = frames.desired
        guard let actual = WindowSceneCapture.currentFrame(id) else { throw FillProbeError.missingWindow }
        fill.update(desired: desired, actual: actual)
        guard fill.visible else { throw FillProbeError.pixels("landing has no fill to retire") }
        kill(child.processIdentifier, SIGCONT); kill(child.processIdentifier, SIGUSR1)
        let deadline = CACurrentMediaTime() + 2
        var lastFrame = CGRect.null
        var lastColor: NSColor?
        repeat {
            await nextCheck()
            guard let observed = WindowSceneCapture.currentFrame(id) else { continue }
            lastFrame = observed
            fill.update(desired: desired, actual: observed)
            guard observed.approxEqual(desired, tolerance: 0.25) else { continue }
            guard !fill.visible else { throw FillProbeError.pixels("fill remained after landing") }
            let landed = try screenshot(area, label: "landed", window: id)
            let sample = try color(landed, x: desired.minX + 90 - area.minX,
                                   y: desired.maxY - 90 - area.minY, area: area)
            lastColor = sample
            if sample.blueComponent > 0.9, sample.redComponent < 0.2 {
                print("real_window_landing_and_live_content true")
                return
            }
        } while CACurrentMediaTime() < deadline
        if FillProbeFixture.style == .browser, CommandLine.arguments.contains("--background") {
            let own = Set(NSApp.windows.filter { $0.windowNumber > 0 }.map { CGWindowID($0.windowNumber) })
            if !WindowSceneCapture.canPresent([desired], participants: [id], excluding: own) {
                throw FillProbeError.interrupted
            }
        }
        let detail = "frame \(lastFrame), goal \(desired)"
        throw FillProbeError.pixels("landing \(detail), pixel \(String(describing: lastColor))")
    }

    private func partialResize(_ fill: WindowResizeFill, child: Process, id: CGWindowID, desired: CGRect,
                               reference: (area: CGRect, image: NSBitmapImageRep)) async throws {
        let (area, before) = reference
        kill(child.processIdentifier, SIGCONT); kill(child.processIdentifier, SIGUSR2)
        let deadline = CACurrentMediaTime() + 2
        let partial = CGRect(x: desired.minX, y: desired.minY,
                             width: desired.width - 200, height: desired.height - 50)
        repeat {
            await nextCheck()
            guard let actual = WindowSceneCapture.currentFrame(id), actual.approxEqual(partial, tolerance: 0.25) else {
                continue
            }
            fill.update(desired: desired, actual: actual)
            await nextCheck()
            let image = try screenshot(area, label: "partial", window: id)
            for offset in [CGFloat(100), 180, 300, 480] {
                let expected = try color(before, x: actual.minX + offset - area.minX,
                                         y: actual.maxY - 55 - area.minY, area: area)
                let extended = try color(image, x: actual.minX + offset - area.minX,
                                         y: actual.maxY + 25 - area.minY, area: area)
                guard equal(expected, extended) else {
                    throw FillProbeError.pixels("sidebar width changed during resize")
                }
            }
            print("sidebar_width_preserved_during_live_resize true")
            return
        } while CACurrentMediaTime() < deadline
        throw FillProbeError.pixels("partial resize did not arrive")
    }

    private func screenshot(_ area: CGRect, label: String, window id: CGWindowID) throws -> NSBitmapImageRep {
        if CommandLine.arguments.contains("--background") {
            return try FillProbeCapture.background(area, label: label, window: id)
        }
        let own = Set(NSApp.windows.filter { $0.windowNumber > 0 }.map { CGWindowID($0.windowNumber) })
        guard WindowSceneCapture.canPresent([area], participants: [id], excluding: own) else {
            throw FillProbeError.interrupted
        }
        CATransaction.flush()
        let shot = Process()
        shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let path = "/tmp/catwm-fill-refined-\(label).png"
        let region = "\(Int(area.minX)),\(Int(area.minY)),\(Int(area.width)),\(Int(area.height))"
        shot.arguments = ["-x", "-R\(region)", path]
        try shot.run(); shot.waitUntilExit()
        guard shot.terminationStatus == 0,
              let image = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path))) else {
            throw FillProbeError.pixels(label)
        }
        return image
    }
}
