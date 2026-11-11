import AppKit
@testable import CatWM
@testable import CatWMKit
import CoreMedia
import CoreVideo
import Testing

@MainActor struct NativeBufferGeometryTests {
    @Test(arguments: [CGFloat(1), 2]) func nativePixelsKeepTheirSizeAcrossViewportChanges(scale: CGFloat) throws {
        let geometry = try #require(NativeBufferGeometry(pixels: CGSize(width: 1000 * scale, height: 800 * scale),
                                                        content: CGRect(x: 30, y: 40, width: 600, height: 400),
                                                        scale: scale, contentScale: 1))
        #expect(geometry.size == CGSize(width: 600, height: 400))
        #expect(geometry.surface == CGRect(x: -30, y: -40, width: 1000, height: 800))
        #expect(geometry.pixels == CGRect(x: 30 * scale, y: 40 * scale, width: 600 * scale, height: 400 * scale))
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, Int(1000 * scale), Int(800 * scale),
                                    kCVPixelFormatType_32BGRA, attributes, &pixelBuffer) == kCVReturnSuccess)
        let buffer = try #require(pixelBuffer)
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                            formatDescriptionOut: &format) == noErr)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                             bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let edge = try #require(context.makeImage())
        let packet = NativeWindowFrame(sample: try #require(sample), geometry: geometry,
                                       right: edge, bottom: edge, received: 0)
        let canvas = NativeWindowBufferLayer()
        canvas.present(packet)
        for width in [CGFloat(400), 600, 900] {
            canvas.viewport(CGRect(x: 100, y: 50, width: width, height: 500))
            #expect(canvas.layer.masksToBounds)
            #expect(canvas.layer.frame.width == width)
            let clip = try #require(canvas.layer.sublayers?.last)
            #expect(clip.frame.size == CGSize(width: 600, height: 400))
            #expect(clip.sublayers?.first?.frame == geometry.surface)
        }
        canvas.close()
    }

    @Test func captureRectDictionaryIsDecodedAtTheBoundary() throws {
        let geometry = try #require(NativeBufferGeometry(pixels: CGSize(width: 2000, height: 1400),
            content: ["X": 0, "Y": 0, "Width": 600, "Height": 400], scale: 2, contentScale: 1))
        #expect(geometry.size == CGSize(width: 600, height: 400))
        #expect(geometry.pixels == CGRect(x: 0, y: 0, width: 1200, height: 800))
        #expect(NativeBufferGeometry(pixels: CGSize(width: 2000, height: 1400),
                                    content: ["Width": 600], scale: 2, contentScale: 1) == nil)
    }

    @Test func downscaledSourcesCannotMasqueradeAsNativePixels() {
        #expect(NativeBufferGeometry(pixels: CGSize(width: 800, height: 600),
                                    content: CGRect(x: 0, y: 0, width: 800, height: 600),
                                    scale: 1, contentScale: 0.5) == nil)
    }

    @Test func invalidSourceRectsAreRejectedAtTheCaptureBoundary() {
        let pixels = CGSize(width: 800, height: 600)
        #expect(NativeBufferGeometry(pixels: pixels, content: .zero, scale: 1, contentScale: 1) == nil)
        #expect(NativeBufferGeometry(pixels: pixels, content: CGRect(x: 0, y: 0, width: 900, height: 600),
                                    scale: 1, contentScale: 1) == nil)
        #expect(NativeBufferGeometry(pixels: pixels, content: CGRect(x: 0, y: 0, width: 800, height: 600),
                                    scale: 0, contentScale: 1) == nil)
    }
}
