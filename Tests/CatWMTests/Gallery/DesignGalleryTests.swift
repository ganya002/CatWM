#if DEBUG
import AppKit
@testable import CatWM
import SwiftUI
import Testing

@MainActor
@Suite struct DesignGalleryTests {
    @Test func showsEveryPaletteColour() {
        let palette = Set(Mirror(reflecting: Palette.catwm).children.compactMap(\.label))
        let shown = Set(ColorToken.all.map(\.name))
        #expect(palette == shown)
    }

    @Test func rendersWithoutEmptyContent() throws {
        let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Fonts")
        let urls = try FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "otf" }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
        let host = NSHostingView(rootView: DesignGalleryView { _ in })
        if let name = ProcessInfo.processInfo.environment["CATWM_GALLERY_APPEARANCE"] {
            host.appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
        }
        host.frame = NSRect(x: 0, y: 0, width: 920, height: 5600)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        #expect(png.count > 20_000)
        if let path = ProcessInfo.processInfo.environment["CATWM_GALLERY_PNG"] {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
