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
        host.frame = NSRect(origin: .zero, size: SwitcherView.size(width: 1710))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}
