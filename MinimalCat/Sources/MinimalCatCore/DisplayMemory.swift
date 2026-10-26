import CoreGraphics
import Foundation

/// Where each window was on each monitor setup, so unplugging, waking or replugging puts it back.
public struct DisplayMemory: Codable, Equatable, Sendable {
    public struct Saved: Codable, Equatable, Sendable {
        public let window: WindowID
        public let bundleID: String?
        public let title: String
        public let display: DisplayID
        public let fraction: CGRect
        public let savedAt: Date
    }

    public static let windowsPerSetup = 200
    public private(set) var setups: [String: [Saved]] = [:]
    public init() {}

    public mutating func save(_ windows: [WindowInfo], on displays: [Display], at now: Date = Date()) {
        guard !displays.isEmpty else { return }
        let fresh = windows.compactMap { window -> Saved? in
            guard let display = Geometry.display(containing: window.frame, in: displays) else { return nil }
            return Saved(window: window.id, bundleID: window.bundleID, title: window.title, display: display.id,
                         fraction: Geometry.fraction(of: window.frame, in: display), savedAt: now)
        }
        let key = DisplaySet(displays).key
        let present = Set(fresh.map(\.window))
        let kept = (setups[key] ?? []).filter { !present.contains($0.window) }
        setups[key] = Array((fresh + kept).sorted { $0.savedAt > $1.savedAt }.prefix(Self.windowsPerSetup))
    }

    /// The moves that put the windows back where they were the last time these monitors were connected.
    public func restore(_ windows: [WindowInfo], on displays: [Display]) -> [Move] {
        guard var saved = setups[DisplaySet(displays).key] else { return [] }
        let byID = Dictionary(displays.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var moves: [Move] = []
        for window in windows {
            let index = saved.firstIndex { $0.window == window.id && $0.bundleID == window.bundleID }
                ?? saved.firstIndex { $0.bundleID == window.bundleID && $0.title == window.title && !$0.title.isEmpty }
            guard let index else { continue }
            let entry = saved.remove(at: index)
            guard let display = byID[entry.display] else { continue }
            let target = Geometry.absolute(entry.fraction, in: display)
            if !Geometry.approxEqual(target, window.frame) {
                moves.append(Move(window: window.id, start: window.frame, end: target))
            }
        }
        return moves
    }
}
