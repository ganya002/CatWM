import AppKit

package final class DesktopMenuBarCover {
    package static let shared = DesktopMenuBarCover()
    private typealias Capture = @convention(c) (CGDirectDisplayID, CGRect) -> Unmanaged<CGImage>?
    private typealias Connection = @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32
    private typealias CaptureWindows = @convention(c) (
        Int32, UnsafePointer<UInt32>, Int32, UInt32, CGRect
    ) -> Unmanaged<CFArray>?
    private static let captureImage: Capture? = symbol(
        "CGDisplayCreateImageForRect", in: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    private static let newConnection: Connection? = symbol("SLSNewConnection")
    private static let connection: Int32? = {
        var connection: Int32 = 0
        guard let newConnection, newConnection(0, &connection) == 0, connection != 0 else { return nil }
        return connection
    }()
    private static let captureWindows: CaptureWindows? = symbol("SLSHWCaptureWindowListInRect")

    package func prepare() {
        let display = CGMainDisplayID()
        Task { @MainActor in
            if let screen = Screen.all().first { prewarm(on: screen) }
        }
        DispatchQueue.global(qos: .userInteractive).async {
            guard Permission.screenRecording.isGranted, let captureImage = Self.captureImage else { return }
            _ = captureImage(display, CGRect(x: 0, y: 0, width: 1, height: 1))?.takeRetainedValue()
        }
    }

    @MainActor private final class Pending {
        package let display: CGDirectDisplayID
        package let source: UInt64
        package let started = ProcessInfo.processInfo.systemUptime
        package let image: Task<CGImage?, Never>
        package let panel: CatWMPanel
        package var target: UInt64?

        package init(display: CGDirectDisplayID, source: UInt64, image: Task<CGImage?, Never>, panel: CatWMPanel) {
            self.display = display
            self.source = source
            self.image = image
            self.panel = panel
        }

        package var isFresh: Bool { ProcessInfo.processInfo.systemUptime - started < 0.5 }

        package func move(to target: UInt64) {
            guard self.target != target else { return }
            self.target = target
            _ = NativeSpaceMove.move(window: CGWindowID(panel.windowNumber), to: target)
        }
    }
    @MainActor private var pending: Pending?
    @MainActor private var spare: CatWMPanel?

    @MainActor package func begin(on screen: Screen, source: UInt64, target: UInt64) {
        if let pending, pending.display == screen.id, pending.source == source, pending.isFresh {
            pending.move(to: target)
            return
        }
        discard()
        guard DesktopMenuBarNative.theme(source) == 1, let image = Self.image(on: screen) else { return }
        let next = Pending(display: screen.id, source: source, image: image, panel: panel(on: screen))
        next.move(to: target)
        pending = next
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(1)) } catch { return } // style-ok: drop an unused early capture
            if pending === next { discard() }
        }
    }

    @MainActor package func capture(on screen: Screen, source: UInt64, target: UInt64) async -> CatWMPanel? {
        guard let early = pending, early.display == screen.id, early.source == source, early.isFresh else {
            discard()
            guard let task = Self.image(on: screen), let image = await task.value else { return nil }
            return await show(image, in: panel(on: screen), screen: screen, source: source, target: target)
        }
        pending = nil
        if early.target != target { early.move(to: target) }
        guard let image = await early.image.value else { recycle(early.panel); return nil }
        return await show(image, in: early.panel, screen: screen, source: source, target: target)
    }

    @MainActor private func discard() {
        pending?.image.cancel()
        recycle(pending?.panel)
        pending = nil
    }

    private static func menuHeight(_ screen: Screen) -> CGFloat {
        guard let nsScreen = screen.nsScreen else { return 0 }
        return nsScreen.frame.maxY - nsScreen.visibleFrame.maxY
    }

    @MainActor private static func image(on screen: Screen) -> Task<CGImage?, Never>? {
        let height = menuHeight(screen)
        guard height > 0, let captureImage else { return nil }
        let id = screen.id, rect = CGRect(x: 0, y: 0, width: screen.frame.width, height: height)
        let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        return Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled, Permission.screenRecording.isGranted, !Task.isCancelled else { return nil }
            return windowsImage(in: global) ?? captureImage(id, rect)?.takeRetainedValue()
        }
    }

    private static func windowsImage(in rect: CGRect) -> CGImage? {
        guard let connection, let captureWindows,
              let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let windows = list.compactMap { info -> UInt32? in
            guard (info[kCGWindowLayer as String] as? Int).map({ $0 >= menuLevel }) == true,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.intersects(rect),
                  let number = info[kCGWindowNumber as String] as? UInt32 else { return nil }
            return number
        }
        guard !windows.isEmpty else { return nil }
        let images = windows.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.flatMap { captureWindows(connection, $0, Int32(buffer.count), 0, rect) }
        }
        return (images?.takeRetainedValue() as? [CGImage])?.first
    }

    private static func panelFrame(on screen: Screen) -> CGRect {
        let height = menuHeight(screen), frame = screen.nsScreen?.frame ?? .zero
        return CGRect(x: frame.minX, y: frame.maxY - height, width: screen.frame.width, height: height)
    }

    @MainActor package func prewarm(on screen: Screen) {
        guard spare == nil, Self.menuHeight(screen) > 0 else { return }
        spare = Self.makePanel(frame: Self.panelFrame(on: screen))
    }

    @MainActor package func panel(on screen: Screen) -> CatWMPanel {
        let frame = Self.panelFrame(on: screen)
        guard let ready = spare else { return Self.makePanel(frame: frame) }
        spare = nil
        if ready.frame != frame { ready.setFrame(frame, display: false) }
        return ready
    }

    @MainActor package func recycle(_ panel: CatWMPanel?) {
        guard let panel else { return }
        if panel.isVisible {
            DesktopMenuBarNative.orderOut(CGWindowID(panel.windowNumber))
            panel.orderOut(nil)
        }
        (panel.contentView as? NSImageView)?.image = nil
        if spare == nil || spare === panel { spare = panel } else { panel.close() }
    }

    @MainActor package static func makePanel(
        frame: CGRect, level: NSWindow.Level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
    ) -> CatWMPanel {
        let panel = CatWMPanel(role: .fullscreenFX, frame: frame)
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        panel.level = level
        let view = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        view.imageScaling = .scaleAxesIndependently
        panel.contentView = view
        return panel
    }

    @MainActor private func show(_ image: CGImage, in panel: CatWMPanel, screen: Screen,
                                 source: UInt64, target: UInt64) async -> CatWMPanel? {
        let window = CGWindowID(panel.windowNumber)
        var placed = Spaces.of(window: window) == [target]
        if !placed, NativeSpaceMove.move(window: window, to: target) {
            placed = await poll(0.1, every: 250_000) { Spaces.of(window: window) == [target] }
        }
        guard placed, Spaces.current(display: screen.uuid) == source else { recycle(panel); return nil }
        (panel.contentView as? NSImageView)?.image = NSImage(cgImage: image, size: panel.frame.size)
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        return panel
    }
}
