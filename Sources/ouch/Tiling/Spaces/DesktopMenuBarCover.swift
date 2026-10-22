import AppKit

enum DesktopMenuBarCover {
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

    static func prepare() {
        guard Permission.screenRecording.isGranted, let captureImage else { return }
        let display = CGMainDisplayID()
        DispatchQueue.global(qos: .userInteractive).async {
            _ = captureImage(display, CGRect(x: 0, y: 0, width: 1, height: 1))?.takeRetainedValue()
        }
    }

    @MainActor private final class Pending {
        let display: CGDirectDisplayID
        let source: UInt64
        let started = ProcessInfo.processInfo.systemUptime
        let image: Task<CGImage?, Never>
        let panel: OuchPanel
        var target: UInt64?

        init(display: CGDirectDisplayID, source: UInt64, image: Task<CGImage?, Never>, panel: OuchPanel) {
            self.display = display
            self.source = source
            self.image = image
            self.panel = panel
        }

        var isFresh: Bool { ProcessInfo.processInfo.systemUptime - started < 0.5 }

        func move(to target: UInt64) {
            self.target = target
            _ = NativeSpaceMove.move(window: CGWindowID(panel.windowNumber), to: target)
        }
    }
    @MainActor private static var pending: Pending?

    @MainActor static func begin(on screen: Screen, source: UInt64, target: UInt64) {
        discard()
        guard DesktopMenuBarNative.theme(source) == 1, let image = image(on: screen) else { return }
        let next = Pending(display: screen.id, source: source, image: image, panel: panel(on: screen))
        next.move(to: target)
        next.panel.orderFrontRegardless()
        pending = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated { if pending === next { discard() } }
        }
    }

    @MainActor static func capture(on screen: Screen, source: UInt64, target: UInt64) async -> OuchPanel? {
        guard let early = pending, early.display == screen.id, early.source == source, early.isFresh else {
            discard()
            guard let task = image(on: screen), let image = await task.value else { return nil }
            return await show(image, in: panel(on: screen), screen: screen, source: source, target: target)
        }
        pending = nil
        if early.target != target { early.move(to: target) }
        guard let image = await early.image.value else { early.panel.close(); return nil }
        return await show(image, in: early.panel, screen: screen, source: source, target: target)
    }

    @MainActor private static func discard() {
        pending?.panel.close()
        pending = nil
    }

    private static func menuHeight(_ screen: Screen) -> CGFloat {
        screen.nsScreen.frame.maxY - screen.nsScreen.visibleFrame.maxY
    }

    @MainActor private static func image(on screen: Screen) -> Task<CGImage?, Never>? {
        let height = menuHeight(screen)
        guard height > 0, Permission.screenRecording.isGranted, let captureImage else { return nil }
        let id = screen.id, rect = CGRect(x: 0, y: 0, width: screen.frame.width, height: height)
        let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        return Task.detached(priority: .userInitiated) {
            windowsImage(in: global) ?? captureImage(id, rect)?.takeRetainedValue()
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

    @MainActor private static func panel(on screen: Screen) -> OuchPanel {
        let height = menuHeight(screen)
        let frame = CGRect(x: screen.nsScreen.frame.minX, y: screen.nsScreen.frame.maxY - height,
                           width: screen.frame.width, height: height)
        let panel = OuchPanel(role: .fullscreenFX, frame: frame)
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        let view = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        view.imageScaling = .scaleAxesIndependently
        panel.contentView = view
        return panel
    }

    @MainActor private static func show(_ image: CGImage, in panel: OuchPanel, screen: Screen,
                                        source: UInt64, target: UInt64) async -> OuchPanel? {
        let window = CGWindowID(panel.windowNumber)
        var placed = Spaces.of(window: window) == [target]
        if !placed, NativeSpaceMove.move(window: window, to: target) {
            placed = await poll(0.1, every: 250_000) { Spaces.of(window: window) == [target] }
        }
        guard placed, Spaces.current(display: screen.uuid) == source else { panel.close(); return nil }
        (panel.contentView as? NSImageView)?.image = NSImage(cgImage: image, size: panel.frame.size)
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        return panel
    }
}
