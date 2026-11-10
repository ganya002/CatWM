import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite struct DesktopWallpaperPaintTests {
    private func picture(dim: Double = 1, inverted: Bool = false) throws -> CGImage {
        let width = 64, height = 40
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let values = [20 + column * 3, 20 + row * 5, 20 + (column + row) * 2]
                for channel in 0..<3 {
                    let value = inverted ? 255 - values[channel] : values[channel]
                    bytes[(row * width + column) * 4 + channel] = UInt8(Double(value) * dim)
                }
            }
        }
        let data = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: data, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @Test func theSamePictureMatchesAcrossCaptureIntensity() throws {
        let expected = try picture()
        #expect(DesktopWallpaperCover.matches(expected, expected))
        #expect(DesktopWallpaperCover.matches(expected, try picture(dim: 0.7)))
    }

    @Test func aBlackFrameDoesNotCountAsTheChosenPhoto() throws {
        #expect(!DesktopWallpaperCover.matches(try picture(), try picture(dim: 0)))
    }

    @Test func aDifferentPhotoDoesNotCountAsPainted() throws {
        #expect(!DesktopWallpaperCover.matches(try picture(), try picture(inverted: true)))
    }

    @Test func anOpaquePlaceholderDoesNotCountAsPainted() throws {
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 45.0 / 255, green: 45.0 / 255, blue: 49.0 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let placeholder = try #require(context.makeImage())
        #expect(!DesktopWallpaperCover.matches(try picture(), placeholder))
    }
}
