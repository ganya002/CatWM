import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_WINDOW_SERVER"] == "1"), .serialized)
struct DesktopWallpaperScopeTests {
    @Test func anActivatedCoverStopsJoiningOtherDesktops() async throws {
        _ = NSApplication.shared
        let screen = try #require(Screen.all().first)
        let space = Spaces.current(display: screen.uuid)
        try #require(space != 0)
        let panel = DesktopMenuBarCover.makePanel(frame: try #require(screen.nsScreen?.frame),
            level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let lease = DesktopWallpaperCover.Lease(
            owner: .shared, panel: panel, image: image, screen: screen, target: space)
        defer { lease.drop() }
        lease.end(shown: true, settings: .init(duration: 0, curve: .easeOut, bounce: 0))
        let bound = await poll(0.2) { Spaces.of(window: CGWindowID(panel.windowNumber)) == [space] }
        #expect(bound)
        #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!panel.isVisible && !panel.canBecomeKey && !panel.canBecomeMain)
    }
}
