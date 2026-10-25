import AppKit
@testable import CatWM
import SwiftUI
import Testing

@MainActor
@Suite struct SwitcherViewTests {
    @Test func everyStateDraws() throws {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.prefix(6)
        let items = apps.enumerated().map { index, app in
            SwitcherItem(id: CGWindowID(index + 1), pid: app.processIdentifier, app: app.localizedName ?? "",
                         title: "Window \(index + 1)", workspace: "\(index % 3 + 1)",
                         size: CGSize(width: [1440, 700, 1200, 2400, 900, 1000][index], height: 900))
        }
        let model = SwitcherModel()
        model.shown = true
        model.begin(items, selection: 1)
        var shots = ["icons": try render(model)]
        model.begin(items, selection: 1, previews: true)
        for item in items.dropLast() {
            model.setPreview(Self.fakeWindow(index: Int(item.id), size: item.size), for: item.id)
        }
        shots["previews"] = try render(model)
        model.peeking = true
        shots["peek"] = try render(model)
        model.type("w")
        shots["search"] = try render(model)
        #expect(shots.values.allSatisfy { $0.count > 5_000 })
        if let folder = ProcessInfo.processInfo.environment["CATWM_SWITCHER_PNG"] {
            for (name, png) in shots {
                try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
            }
        }
    }

    @Test func peekUsesOneScaleThatFitsEveryWindow() {
        let room = CGSize(width: 1600, height: 800)
        let small = SwitcherItem(id: 1, pid: 1, app: "App", title: "", size: CGSize(width: 800, height: 600))
        let tall = SwitcherItem(id: 2, pid: 1, app: "App", title: "", size: CGSize(width: 1000, height: 1600))
        #expect(SwitcherView.peekScale([small], room: room) == 1)
        let scale = SwitcherView.peekScale([small, tall], room: room)
        #expect(SwitcherView.scaled(tall.size, by: scale) == CGSize(width: 500, height: 800))
        #expect(SwitcherView.scaled(small.size, by: scale) == CGSize(width: 400, height: 300))
    }

    @Test func barTilesShareOneHeightAndFitTheRoom() {
        let room = CGSize(width: 1000, height: 900)
        let items = [CGSize(width: 1600, height: 1000), CGSize(width: 400, height: 500)].enumerated().map {
            SwitcherItem(id: CGWindowID($0 + 1), pid: 1, app: "App", title: "", size: $1)
        }
        let height = SwitcherView.barHeight(items, room: room)
        let tiles = items.map { SwitcherView.tileSize($0, height: height, room: room) }
        #expect(tiles.map(\.width).reduce(0, +) <= room.width * SwitcherView.Tile.barWidthShare)
        #expect(tiles[0].height == tiles[1].height)
        #expect(tiles[0].width > tiles[1].width * 1.9)
    }

    private static func fakeWindow(index: Int, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor(hue: CGFloat(index) / 7, saturation: 0.5, brightness: 0.8, alpha: 1).setFill()
            rect.fill()
            NSColor.white.setFill()
            NSRect(x: 0, y: rect.height - 24, width: rect.width, height: 24).fill()
            return true
        }
    }

    private func render(_ model: SwitcherModel) throws -> Data {
        let host = NSHostingView(rootView: SwitcherView(model: model).background(Color.gray))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: CGSize(width: 1710, height: 900))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}
