import AppKit
import CoreMedia
import CoreVideo
import QuartzCore
import ScreenCaptureKit

package struct NativeWindowFrame {
    let sample: CMSampleBuffer
    let geometry: NativeBufferGeometry
    let right: CGImage
    let bottom: CGImage
    let received: CFTimeInterval
}

final class NativeWindowStream: NSObject, SCStreamOutput, SCStreamDelegate {
    enum Failure: Error { case permission, missingWindow }
    private let queue = DispatchQueue(label: "catwm.live-window", qos: .userInitiated)
    private let lock = NSLock()
    private var latest: NativeWindowFrame?
    private var stream: SCStream?
    private var config: SCStreamConfiguration?
    private var received = 0
    var frame: NativeWindowFrame? { lock.withLock { latest } }
    var frameCount: Int { lock.withLock { received } }

    func start(window: SCWindow, capacity: CGSize, rate: Int) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw Failure.permission }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int(ceil(capacity.width * scale))
        config.height = Int(ceil(capacity.height * scale))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(rate))
        config.scalesToFit = false
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        config.queueDepth = 5
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        self.config = config
        do { try await stream.startCapture() } catch {
            Log.attempt("detach failed live stream") { try stream.removeStreamOutput(self, type: .screen) }
            self.stream = nil
            throw error
        }
    }

    func pace(_ rate: Int) {
        guard let stream, let config, config.minimumFrameInterval.timescale != rate else { return }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(rate))
        stream.updateConfiguration(config) { error in
            if let error { Log.info("live-window: pace \(rate) failed: \(error)") }
        }
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        do { try await stream.stopCapture() } catch { Log.info("live-window: stop failed: \(error)") }
        Log.attempt("detach live stream") { try stream.removeStreamOutput(self, type: .screen) }
        lock.withLock { latest = nil }
    }

    func stream(_: SCStream, didStopWithError error: Error) {
        lock.withLock { latest = nil }
        Log.info("live-window: capture stopped: \(error)")
    }

    func stream(_: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen { receive(sample) }
    }

    func receive(_ sample: CMSampleBuffer) {
        guard sample.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]])?.first,
              let status = info[.status] as? Int, status == SCFrameStatus.complete.rawValue else { return }
        guard let buffer = sample.imageBuffer,
              let values = info[.contentRect] as? [String: Any],
              let scaleValue = info[.scaleFactor] as? Double,
              let contentScaleValue = info[.contentScale] as? Double,
              let geometry = NativeBufferGeometry(pixels: CGSize(width: CVPixelBufferGetWidth(buffer),
                                                                 height: CVPixelBufferGetHeight(buffer)),
                                                  content: values, scale: CGFloat(scaleValue),
                                                  contentScale: CGFloat(contentScaleValue)),
              let edges = Self.edges(buffer, geometry: geometry) else {
            lock.withLock { latest = nil }
            return
        }
        let frame = NativeWindowFrame(sample: sample, geometry: geometry, right: edges.right, bottom: edges.bottom,
                                      received: CACurrentMediaTime())
        let first = lock.withLock { latest = frame; received += 1; return received == 1 }
        if first { Log.debug("live-window: first native buffer \(geometry.size) scale \(geometry.scale)") }
    }

    private static func edges(_ buffer: CVPixelBuffer, geometry: NativeBufferGeometry)
        -> (right: CGImage, bottom: CGImage)? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let bounds = geometry.pixels.integral.intersection(CGRect(x: 0, y: 0,
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
        let width = Int(bounds.width), height = Int(bounds.height)
        let left = Int(bounds.minX), top = Int(bounds.minY)
        let inset = max(1, Int(ceil(geometry.scale * 3)))
        let rightX = left + max(0, width - inset - 1)
        let bottomY = top + max(0, height - inset - 1)
        func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: width * 4, space: space,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                            .union(.byteOrder32Little), provider: provider, decode: nil,
                           shouldInterpolate: false, intent: .defaultIntent)
        }
        var right: [UInt8] = [], bottom: [UInt8] = []
        for y in 0..<height {
            let offset = (top + y) * stride + rightX * 4
            right.append(contentsOf: UnsafeBufferPointer(start: pixels + offset, count: 4))
        }
        for x in 0..<width {
            let offset = bottomY * stride + (left + x) * 4
            bottom.append(contentsOf: UnsafeBufferPointer(start: pixels + offset, count: 4))
        }
        guard let rightImage = image(right, width: 1, height: height),
              let bottomImage = image(bottom, width: width, height: 1) else { return nil }
        return (rightImage, bottomImage)
    }
}
