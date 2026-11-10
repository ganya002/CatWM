import AppKit
import QuartzCore

package final class WindowFrameClock: NSObject {
    package let displayID: CGDirectDisplayID?
    private var link: CADisplayLink?
    private let update: (CFTimeInterval) -> Void

    package init(screen: NSScreen, update: @escaping (CFTimeInterval) -> Void) {
        displayID = screen.displayID
        self.update = update
        super.init()
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        let rate = Float(screen.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, rate), maximum: rate, preferred: rate)
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    package func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func frame(_ link: CADisplayLink) { update(link.targetTimestamp) }
}
