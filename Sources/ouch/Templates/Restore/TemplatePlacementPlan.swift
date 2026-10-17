import CoreGraphics
import Foundation

enum TemplatePlacementPlan {
    enum DesktopMove: Equatable {
        case stay
        case move
        case unavailable
    }

    static func preferredDisplays(_ template: WorkspaceTemplate, mapping: [String: String]) -> [String: String] {
        var preferred: [String: String] = [:]
        for display in template.displays.filter(\.isMain) + template.displays.filter({ !$0.isMain }) {
            guard let target = mapping[display.id], preferred[target] == nil else { continue }
            preferred[target] = display.id
        }
        return preferred
    }

    static func releaseHeldWindow(scanStarted: Date, heldSince: Date, minimized: Bool, fullscreen: Bool, restoring: Bool) -> Bool {
        !restoring && scanStarted > heldSince && !minimized && !fullscreen
    }

    static func zoomedWindow(savedDisplay: String, window: CGWindowID, zoomed: Bool, preferredSavedDisplay: String?) -> CGWindowID? {
        guard zoomed, savedDisplay == preferredSavedDisplay else { return nil }
        return window
    }

    static func desktopMove(membership: [UInt64], destination: UInt64) -> DesktopMove {
        if membership.isEmpty { return .unavailable }
        return membership.contains(destination) ? .stay : .move
    }

    static func writerBarrier<ID: Hashable>(placed: Set<ID>, busy: Set<ID>) -> Set<ID> {
        placed.intersection(busy)
    }
}
