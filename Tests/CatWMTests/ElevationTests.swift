import AppKit
@testable import CatWM
@testable import CatWMKit
import SwiftUI
import Testing

@MainActor
@Suite struct ElevationTests {
    @Test(arguments: [Elevation.popover, .float])
    func shadowFadesInsideItsRoom(_ elevation: Elevation) throws {
        let host = NSHostingView(rootView: ShadowSample(elevation: elevation))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let background = darkness(rep, x: 2, y: rep.pixelsHigh - 2)
        let top = darkness(rep, x: rep.pixelsWide / 2, y: 2)
        let bottom = darkness(rep, x: rep.pixelsWide / 2, y: rep.pixelsHigh - 2)
        let scale = CGFloat(rep.pixelsHigh) / size.height
        let inShadow = darkness(rep, x: rep.pixelsWide / 2, y: Int((elevation.room - 8) * scale))
        #expect(top < background + 6)
        #expect(bottom < background + 6)
        #expect(inShadow > background + 20)
    }

    private func darkness(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Int {
        let color = (rep.colorAt(x: x, y: y) ?? .clear).usingColorSpace(.sRGB) ?? .clear
        return Int(((1 - (color.redComponent + color.greenComponent + color.blueComponent) / 3) * 255).rounded())
    }
}

private struct ShadowSample: View {
    let elevation: Elevation

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape.fill(Color.white)
            .frame(width: 140, height: 72)
            .elevation(elevation, in: shape)
            .padding(elevation.room)
            .background(Color(white: 0.92))
    }
}
