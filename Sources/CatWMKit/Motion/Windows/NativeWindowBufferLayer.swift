import AppKit
import AVFoundation
import QuartzCore

final class NativeWindowBufferLayer {
    let layer = CALayer()
    private let videoClip = CALayer()
    private let video = AVSampleBufferDisplayLayer()
    private let right = CALayer()
    private let bottom = CALayer()
    private var geometry: NativeBufferGeometry?
    private var clock: WindowFrameClock?
    private var stamp: CMTime?

    init() {
        layer.masksToBounds = true
        videoClip.masksToBounds = true
        video.videoGravity = .resize
        for edge in [right, bottom] {
            edge.magnificationFilter = .nearest
            edge.minificationFilter = .nearest
            layer.addSublayer(edge)
        }
        videoClip.addSublayer(video)
        layer.addSublayer(videoClip)
    }

    func viewport(_ frame: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = frame
        layout()
        CATransaction.commit()
    }

    func present(_ frame: NativeWindowFrame) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(frame.sample)
        guard timestamp != stamp, video.sampleBufferRenderer.isReadyForMoreMediaData else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stamp = timestamp
        geometry = frame.geometry
        right.contents = frame.right
        bottom.contents = frame.bottom
        right.contentsScale = frame.geometry.scale
        bottom.contentsScale = frame.geometry.scale
        layout()
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(frame.sample, createIfNecessary: true) {
            let values = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(values, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        video.sampleBufferRenderer.enqueue(frame.sample)
        CATransaction.commit()
    }

    func animate(to target: CGRect, on screen: NSScreen, duration: Double, done: @escaping () -> Void) {
        clock?.stop()
        guard duration > 0 else { viewport(target); done(); return }
        let source = layer.frame, start = CACurrentMediaTime()
        clock = WindowFrameClock(screen: screen) { [weak self] time in
            guard let self else { return }
            let fraction = min(1, max(0, (time - start) / duration))
            let progress = AnimationCurve.easeInOut.progress(fraction, bounce: 0)
            func value(_ from: CGFloat, _ destination: CGFloat) -> CGFloat { from + (destination - from) * progress }
            self.viewport(CGRect(x: value(source.minX, target.minX), y: value(source.minY, target.minY),
                                 width: value(source.width, target.width), height: value(source.height, target.height)))
            if fraction >= 1 { self.clock?.stop(); self.clock = nil; done() }
        }
    }

    private func layout() {
        guard let geometry else { return }
        videoClip.frame = CGRect(origin: .zero, size: geometry.size)
        video.frame = geometry.surface
        let bounds = layer.bounds
        right.frame = CGRect(x: 0, y: 0, width: bounds.width, height: geometry.size.height)
        bottom.frame = CGRect(x: 0, y: geometry.size.height, width: bounds.width,
                              height: max(0, bounds.height - geometry.size.height))
    }

    func close() {
        clock?.stop()
        clock = nil
        video.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        layer.removeFromSuperlayer()
    }
}
