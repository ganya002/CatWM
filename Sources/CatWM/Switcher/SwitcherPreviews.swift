import AppKit
import ScreenCaptureKit

enum SwitcherPreviews {
    static let thumbPixels: CGFloat = 400
    static let peekPixels: CGFloat = 1600

    static func capture(_ ids: [CGWindowID], pixels: CGFloat,
                        deliver: @escaping @MainActor (CGWindowID, NSImage) -> Void) -> Task<Void, Never>? {
        guard ScreenRecording.shared.isGranted, !ids.isEmpty else { return nil }
        return Task.detached(priority: .userInitiated) {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            } catch {
                Log.info("switcher: no window previews: \(error.localizedDescription)")
                return
            }
            let rank = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            let found = content.windows.filter { rank[$0.windowID] != nil }
                .sorted { rank[$0.windowID] ?? 0 < rank[$1.windowID] ?? 0 }
            await withTaskGroup(of: Void.self) { group in
                for window in found {
                    group.addTask {
                        guard !Task.isCancelled, let image = await shot(window, pixels: pixels),
                              !Task.isCancelled else { return }
                        await deliver(window.windowID, image)
                    }
                }
            }
        }
    }

    private static func shot(_ window: SCWindow, pixels: CGFloat) async -> NSImage? {
        let frame = window.frame
        guard frame.width >= 40, frame.height >= 40 else { return nil }
        let width = min(pixels, frame.width * 2)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(width)
        configuration.height = max(1, Int(width * frame.height / frame.width))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
            return NSImage(cgImage: image, size: frame.size)
        } catch {
            return nil
        }
    }
}
