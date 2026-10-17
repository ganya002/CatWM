#if DEBUG
import AppKit
import SwiftUI
import Testing
@testable import ouch

@MainActor
@Suite struct DesignGalleryTests {
    @Test func rendersWithoutEmptyContent() throws {
        let host = NSHostingView(rootView: DesignGalleryView { _ in })
        host.frame = NSRect(x: 0, y: 0, width: 920, height: 3000)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        #expect(png.count > 20_000)
        if let path = ProcessInfo.processInfo.environment["OUCH_GALLERY_PNG"] {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
