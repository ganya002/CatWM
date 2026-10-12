import AppKit
import QuartzCore

/// Animates windows between frames by stepping their AX frame, then lands, verifies and corrects.
final class Animator {
    struct Move {
        let window: Window
        let to: CGRect
        let bounds: CGRect // visible area of the target screen, used to keep oversized windows on it
    }

    fileprivate struct Item {
        let move: Move
        let from: CGRect
        let start: CFTimeInterval
        let duration: Double
    }

    private var items: [CGWindowID: Item] = [:]
    private var quietUntil: [CGWindowID: CFTimeInterval] = [:]
    private var timer: Timer?
    /// Called when a window turns out to be bigger than its slot even after retrying.
    var onMinimumSize: ((CGWindowID, CGSize) -> Void)?

    /// True while we are moving the window ourselves, so its move/resize notifications are ours.
    func isBusy(_ id: CGWindowID) -> Bool {
        items[id] != nil || (quietUntil[id] ?? 0) > CACurrentMediaTime()
    }

    /// Stops animating a window (it's about to be parked somewhere else).
    func cancel(_ id: CGWindowID) {
        guard let item = items.removeValue(forKey: id) else { return }
        EnhancedUI.resume(item.move.window.pid)
    }

    /// Treat the next move/resize notifications for this window as our own.
    func quiet(_ id: CGWindowID, for seconds: Double = 0.4) {
        quietUntil[id] = CACurrentMediaTime() + seconds
    }

    func animate(_ moves: [Move], duration: Double) {
        let now = CACurrentMediaTime()
        for m in moves {
            let id = m.window.id
            let from: CGRect
            if let running = items[id] {
                from = running.frame(at: now) // retarget smoothly from where it is mid-flight
            } else {
                from = m.window.frame
                EnhancedUI.suspend(m.window.pid)
            }
            if duration < 0.01 || from.isNull || from.approxEqual(m.to, tolerance: 2) {
                items[id] = nil
                land(m)
            } else {
                items[id] = Item(move: m, from: from, start: now, duration: duration)
            }
        }
        if !items.isEmpty && timer == nil {
            let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            tick()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        for (id, item) in items {
            if now - item.start >= item.duration {
                items[id] = nil
                land(item.move)
            } else {
                let f = item.frame(at: now)
                item.move.window.setSize(f.size)
                item.move.window.setPosition(f.origin)
            }
        }
        if items.isEmpty { timer?.invalidate(); timer = nil }
    }

    private func land(_ m: Move) {
        m.window.setFrame(m.to)
        quietUntil[m.window.id] = CACurrentMediaTime() + 0.4
        EnhancedUI.resume(m.window.pid)
        // Many apps apply frames asynchronously or snap to their own grid; check once it settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.verify(m) }
    }

    private func verify(_ m: Move) {
        let w = m.window
        guard items[w.id] == nil else { return } // re-animated since
        var actual = w.frame
        guard !actual.isNull, !actual.approxEqual(m.to, tolerance: 2) else { return }

        quietUntil[w.id] = CACurrentMediaTime() + 0.4
        EnhancedUI.suspend(w.pid)
        w.setFrame(m.to)
        actual = w.frame
        // Still too big => the app has a minimum size. Keep it anchored to its slot but on screen,
        // instead of hanging off the edge or covering the menu bar.
        if !actual.isNull, actual.width > m.to.width + 1 || actual.height > m.to.height + 1 {
            onMinimumSize?(w.id, CGSize(width: actual.width > m.to.width + 1 ? actual.width : 0,
                                        height: actual.height > m.to.height + 1 ? actual.height : 0))
            var o = m.to.origin
            o.x = max(m.bounds.minX, min(o.x, m.bounds.maxX - actual.width))
            o.y = max(m.bounds.minY, min(o.y, m.bounds.maxY - actual.height))
            w.setPosition(o)
        }
        EnhancedUI.resume(w.pid)
    }
}

private extension Animator.Item {
    func frame(at now: CFTimeInterval) -> CGRect {
        let t = min(1, max(0, (now - start) / duration))
        let e = CGFloat(1 - pow(1 - t, 3)) // ease-out cubic
        let to = move.to
        return CGRect(x: from.minX + (to.minX - from.minX) * e,
                      y: from.minY + (to.minY - from.minY) * e,
                      width: from.width + (to.width - from.width) * e,
                      height: from.height + (to.height - from.height) * e).pixelAligned
    }
}
