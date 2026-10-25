import CoreGraphics
import Foundation

struct FocusEcho {
    static let window: TimeInterval = 0.4

    let id: CGWindowID
    let other: pid_t
    let until: Date

    init(id: CGWindowID, other: pid_t, now: Date = Date()) {
        self.id = id
        self.other = other
        until = now.addingTimeInterval(Self.window)
    }

    func matches(_ pid: pid_t?, at now: Date = Date()) -> Bool { pid == other && now < until }
}
