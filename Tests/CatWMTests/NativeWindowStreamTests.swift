@testable import CatWMKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import Testing

struct NativeWindowStreamTests {
    @Test func unsupportedCompleteFramesDiscardThePreviouslyValidBuffer() throws {
        let stream = NativeWindowStream()
        stream.receive(try sample(contentScale: 1))
        #expect(stream.frame != nil)
        stream.receive(try sample(contentScale: 0.5))
        #expect(stream.frame == nil)
    }

    @Test func idleFramesKeepTheLastValidBuffer() throws {
        let stream = NativeWindowStream()
        stream.receive(try sample(contentScale: 1))
        #expect(stream.frame != nil)
        stream.receive(try sample(contentScale: 1, status: .idle))
        #expect(stream.frame != nil)
    }

    private func sample(contentScale: Double, status: SCFrameStatus = .complete) throws -> CMSampleBuffer {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        let image = try #require(buffer)
        var description: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image,
                                                           formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image,
            formatDescription: try #require(description), sampleTiming: &timing,
            sampleBufferOut: &sample) == noErr)
        let result = try #require(sample)
        let attachments = try #require(CMSampleBufferGetSampleAttachmentsArray(result, createIfNecessary: true))
        let values = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: NSMutableDictionary.self)
        let info: [SCStreamFrameInfo: Any] = [
            .status: status.rawValue, .scaleFactor: 1.0, .contentScale: contentScale,
            .contentRect: CGRect(x: 0, y: 0, width: 32, height: 32).dictionaryRepresentation
        ]
        for (key, value) in info {
            values[key.rawValue] = value
        }
        return result
    }
}
