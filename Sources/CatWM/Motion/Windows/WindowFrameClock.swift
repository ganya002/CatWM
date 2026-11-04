import AppKit
import QuartzCore

final class WindowFrameClock: NSObject {
    let displayID: CGDirectDisplayID?
    private var link: CADisplayLink?
    private let update: (CFTimeInterval) -> Void

    init(screen: NSScreen, update: @escaping (CFTimeInterval) -> Void) {
        displayID = screen.displayID
        self.update = update
        super.init()
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        let rate = Float(screen.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, rate), maximum: rate, preferred: rate)
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func frame(_ link: CADisplayLink) { update(link.targetTimestamp) }
}
