import AppKit

enum DesktopMenuBarCover {
    private typealias Capture = @convention(c) (CGDirectDisplayID, CGRect) -> Unmanaged<CGImage>?
    private static let captureImage: Capture? = symbol(
        "CGDisplayCreateImageForRect", in: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")

    static func prepare() {
        guard CGPreflightScreenCaptureAccess(), let captureImage else { return }
        let display = CGMainDisplayID()
        DispatchQueue.global(qos: .userInteractive).async {
            _ = captureImage(display, CGRect(x: 0, y: 0, width: 1, height: 1))?.takeRetainedValue()
        }
    }

    @MainActor static func capture(on screen: Screen, source: UInt64, target: UInt64) async -> OuchPanel? {
        guard CGPreflightScreenCaptureAccess(), let captureImage else { return nil }
        let height = screen.nsScreen.frame.maxY - screen.nsScreen.visibleFrame.maxY
        guard height > 0 else { return nil }
        let id = screen.id, rect = CGRect(x: 0, y: 0, width: screen.frame.width, height: height)
        let image: CGImage? = await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInteractive).async {
                done.resume(returning: captureImage(id, rect)?.takeRetainedValue())
            }
        }
        guard let image, Spaces.current(display: screen.uuid) == source else { return nil }
        return await place(image, height: height, screen: screen, target: target)
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
              await poll(0.1, every: 1_000_000, until: { Spaces.of(window: window) == [target] }) else {
            panel.close(); return nil
        }
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        return panel
    }
}
