import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

struct WindowFillAppearanceTests {
    @Test func titlebarAndBodyKeepTheirOwnColorsAndNativeCornerAlpha() throws {
        let appearance = try #require(WindowFillAppearance(image: image(), size: CGSize(width: 20, height: 15)))
        let edge = NSBitmapImageRep(cgImage: appearance.rightEdge)
        let header = try #require(edge.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        let body = try #require(edge.colorAt(x: 0, y: 15)?.usingColorSpace(.deviceRGB))
        #expect(header.redComponent < 0.2)
        #expect(body.redComponent > 0.8)
        #expect(appearance.sourceSize == CGSize(width: 20, height: 15))
        let outline = NSBitmapImageRep(cgImage: appearance.outline)
        let inverse = NSBitmapImageRep(cgImage: appearance.inverseOutline)
        #expect(try #require(outline.colorAt(x: 0, y: 0)).alphaComponent == 0)
        #expect(try #require(inverse.colorAt(x: 0, y: 0)).alphaComponent == 1)
        let middle = outline.pixelsWide / 2
        #expect(try #require(outline.colorAt(x: middle, y: middle)).alphaComponent == 1)
        #expect(try #require(inverse.colorAt(x: middle, y: middle)).alphaComponent == 0)
        #expect(appearance.outline.width < 40)
        let border = NSBitmapImageRep(cgImage: appearance.border)
        #expect(try #require(border.colorAt(x: middle, y: middle)).alphaComponent == 0)
        #expect(try #require(border.colorAt(x: middle, y: 0)).alphaComponent == 1)
    }

    @Test func repeatedHorizontalResizeReusesThePreparedColors() throws {
        let appearance = try #require(WindowFillAppearance(image: image(), size: CGSize(width: 20, height: 15)))
        #expect(appearance.canFill(from: CGRect(x: 0, y: 0, width: 24, height: 15),
                                   to: CGRect(x: 0, y: 0, width: 28, height: 15)))
    }

    @Test func unsupportedGeometryCannotEnableEarlyNativeShrinking() throws {
        let appearance = try #require(WindowFillAppearance(image: image(), size: CGSize(width: 20, height: 15)))
        let from = CGRect(x: 0, y: 0, width: 20, height: 15)
        #expect(!appearance.canFill(from: from, to: CGRect(x: 0, y: 1, width: 18, height: 15)))
        #expect(!appearance.canFill(from: from, to: CGRect(x: 0, y: 0, width: 1, height: 15)))
        #expect(!appearance.canFill(from: from, to: CGRect(x: 50, y: 0, width: 18, height: 15)))
        #expect(appearance.canFill(from: from, to: CGRect(x: 0, y: 0, width: 18, height: 15)))
    }

    @Test(arguments: [false, true]) func translucentContentCannotBePaintedOverAsAnOpaqueGap(edge: Bool) throws {
        #expect(WindowFillAppearance(image: try image(translucent: true, edge: edge),
                                     size: CGSize(width: 20, height: 15)) == nil)
    }

    @Test(arguments: [1, 2]) func eachEdgeKeepsItsOwnBackgroundWithoutRepeatingText(scale: Int) throws {
        let appearance = try #require(WindowFillAppearance(image: multicolorImage(scale: scale),
                                                           size: CGSize(width: 80, height: 60)))
        let left = NSBitmapImageRep(cgImage: appearance.leftEdge)
        let right = NSBitmapImageRep(cgImage: appearance.rightEdge)
        let bottom = NSBitmapImageRep(cgImage: appearance.bottomEdge)
        let sidebar = try #require(left.colorAt(x: 0, y: 30 * scale)?.usingColorSpace(.deviceRGB))
        let content = try #require(right.colorAt(x: 0, y: 30 * scale)?.usingColorSpace(.deviceRGB))
        #expect(sidebar.blueComponent > 0.4 && sidebar.redComponent < 0.2)
        #expect(content.redComponent > 0.9)
        for x in [10, 60] {
            let status = try #require(bottom.colorAt(x: x * scale, y: 0)?.usingColorSpace(.deviceRGB))
            #expect(status.greenComponent > status.redComponent * 2)
            #expect(status.greenComponent > status.blueComponent)
        }
    }

    @Test func rectangularChromeDoesNotAcquireRoundedCorners() throws {
        let appearance = try #require(WindowFillAppearance(image: multicolorImage(scale: 1, square: true),
                                                           size: CGSize(width: 80, height: 60)))
        let outline = NSBitmapImageRep(cgImage: appearance.outline)
        #expect(try #require(outline.colorAt(x: 0, y: 0)).alphaComponent == 1)
        #expect(try #require(outline.colorAt(x: outline.pixelsWide - 1, y: outline.pixelsHigh - 1))
            .alphaComponent == 1)
        #expect(appearance.minimumSize.width < 5)
    }

    @Test func bottomGrowthPreservesSidebarWidthAsTheWindowGetsWider() throws {
        let appearance = try #require(WindowFillAppearance(image: multicolorImage(scale: 2, statusBar: false),
                                                           size: CGSize(width: 80, height: 60)))
        #expect(abs(appearance.bottomCenter.minX * 80 - 20) < 0.5)
        #expect(appearance.bottomCenter.maxX == 1)
    }

    private func multicolorImage(scale: Int, square: Bool = false, statusBar: Bool = true) throws -> CGImage {
        let width = 80 * scale, height = 60 * scale
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let corner = !square && (x < 2 * scale || x >= width - 2 * scale)
                    && (y < 2 * scale || y >= height - 2 * scale)
                let color: [UInt8] = corner ? [0, 0, 0, 0]
                    : y < 12 * scale ? [40, 50, 60, 255]
                    : statusBar && y >= 52 * scale ? [20, 80, 40, 255]
                    : y < 45 * scale && x % (8 * scale) == 4 * scale ? [0, 0, 0, 255]
                    : x < 20 * scale ? [30, 50, 130, 255] : [240, 245, 250, 255]
                bytes += color
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func image(translucent: Bool = false, edge: Bool = false) throws -> CGImage {
        let width = 40, height = 30
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let corner = (x < 2 || x >= width - 2) && (y < 2 || y >= height - 2)
                let color: [UInt8] = corner ? [0, 0, 0, 0]
                    : translucent && x == (edge ? 0 : width / 2) && y == height / 2 ? [50, 50, 50, 100]
                    : y < 6 ? [32, 40, 55, 255] : [230, 240, 250, 255]
                bytes.replaceSubrange(offset..<(offset + 4), with: color)
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
