import AppKit

enum DesktopMenuBarCover {
    private typealias Capture = @convention(c) (CGDirectDisplayID, CGRect) -> Unmanaged<CGImage>?
    private typealias Connection = @convention(c) () -> Int32
    private typealias CaptureWindows = @convention(c) (
        Int32, UnsafePointer<UInt32>, Int32, UInt32, CGRect
    ) -> Unmanaged<CFArray>?
    private static let captureImage: Capture? = symbol(
        "CGDisplayCreateImageForRect", in: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    private static let connection: Connection? = symbol("SLSMainConnectionID")
    private static let captureWindows: CaptureWindows? = symbol("SLSHWCaptureWindowListInRect")

    static func prepare() {
        guard CGPreflightScreenCaptureAccess(), let captureImage else { return }
        let display = CGMainDisplayID()
        DispatchQueue.global(qos: .userInteractive).async {
            _ = captureImage(display, CGRect(x: 0, y: 0, width: 1, height: 1))?.takeRetainedValue()
        }
    }

    private struct Pending {
        let display: CGDirectDisplayID
        let source: UInt64
        let started: TimeInterval
        let image: Task<CGImage?, Never>
    }
    @MainActor private static var pending: Pending?

    @MainActor static func begin(on screen: Screen, source: UInt64) {
        guard DesktopMenuBarNative.theme(source) == 1, let image = image(on: screen) else { return }
        pending = Pending(display: screen.id, source: source, started: ProcessInfo.processInfo.systemUptime,
                          image: image)
    }

    @MainActor static func capture(on screen: Screen, source: UInt64, target: UInt64) async -> OuchPanel? {
        let early = pending.flatMap { pending in
            pending.display == screen.id && pending.source == source
                && ProcessInfo.processInfo.systemUptime - pending.started < 0.5 ? pending.image : nil
        }
        pending = nil
        guard let task = early ?? image(on: screen), let image = await task.value,
              Spaces.current(display: screen.uuid) == source else { return nil }
        return await place(image, height: menuHeight(screen), screen: screen, target: target)
    }

    private static func menuHeight(_ screen: Screen) -> CGFloat {
        screen.nsScreen.frame.maxY - screen.nsScreen.visibleFrame.maxY
    }

    @MainActor private static func image(on screen: Screen) -> Task<CGImage?, Never>? {
        let height = menuHeight(screen)
        guard height > 0, CGPreflightScreenCaptureAccess(), let captureImage else { return nil }
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
        let windows = list.compactMap { info -> UInt32? in
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.intersects(rect),
                  let number = info[kCGWindowNumber as String] as? UInt32 else { return nil }
            return number
        }
        guard !windows.isEmpty else { return nil }
        let images = windows.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.flatMap { captureWindows(connection(), $0, Int32(buffer.count), 0, rect) }
        }
        return (images?.takeRetainedValue() as? [CGImage])?.first
    }

    @MainActor private static func place(_ image: CGImage, height: CGFloat,
                                         screen: Screen, target: UInt64) async -> OuchPanel? {
        let frame = CGRect(x: screen.nsScreen.frame.minX, y: screen.nsScreen.frame.maxY - height,
                           width: screen.frame.width, height: height)
        let panel = OuchPanel(role: .fullscreenFX, frame: frame)
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let view = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        view.image = NSImage(cgImage: image, size: frame.size)
        view.imageScaling = .scaleAxesIndependently
        panel.contentView = view
        let window = CGWindowID(panel.windowNumber)
        guard NativeSpaceMove.move(window: window, to: target),
              await poll(0.1, every: 250_000, until: { Spaces.of(window: window) == [target] }) else {
            panel.close(); return nil
        }
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        return panel
    }
}
