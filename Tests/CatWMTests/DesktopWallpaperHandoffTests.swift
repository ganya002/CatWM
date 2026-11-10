import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_WALLPAPER_HANDOFF"] == "1"), .serialized)
struct DesktopWallpaperHandoffTests {
    @Test func aDifferentPreviewFadesToTheRealWallpaperWithoutTruncatingALongAnimation() async throws {
        _ = NSApplication.shared
        let screen = try #require(Screen.all().first)
        let space = try #require(UInt64(ProcessInfo.processInfo.environment["CATWM_TEST_OWNED_SPACE"] ?? ""))
        try #require(Spaces.current(display: screen.uuid) == space)
        try #require(CGPreflightScreenCaptureAccess())
        let catalog = Spaces.list(display: screen.uuid)?.ids
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frame = try #require(screen.nsScreen?.frame)
        let panel = DesktopMenuBarCover.makePanel(frame: frame,
            level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1))
        let context = try #require(CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
        let image = try #require(context.makeImage())
        (panel.contentView as? NSImageView)?.image = NSImage(cgImage: image, size: frame.size)
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        let lease = DesktopWallpaperCover.Lease(
            owner: .shared, panel: panel, image: image, screen: screen, target: space)
        defer { lease.drop() }
        lease.end(shown: true, settings: .init(duration: 1.2, curve: .easeOut, bounce: 0))
        let fading = await poll(0.8) { panel.isVisible && panel.alphaValue < 0.99 && panel.alphaValue > 0 }
        #expect(fading, "The destination paint must start a real crossfade before the failure bound")
        let fadeStarted = CACurrentMediaTime()
        let retired = await poll(2) { !panel.isVisible }
        #expect(retired)
        #expect(CACurrentMediaTime() - fadeStarted > 1,
                "The one-second capture bound must not truncate the configured fade")
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(Spaces.current(display: screen.uuid) == space)
        #expect(Spaces.list(display: screen.uuid)?.ids == catalog)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus)
    }
}
