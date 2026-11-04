import CoreGraphics

struct WindowScenePlacement {
    private(set) var requested: CGRect
    private(set) var coverage: CGRect

    init(frame: CGRect) { requested = frame; coverage = frame }

    mutating func retarget(to target: CGRect) {
        let size = CGSize(width: max(requested.width, target.width), height: max(requested.height, target.height))
        let before = CGRect(origin: requested.origin, size: size)
        let after = CGRect(origin: target.origin, size: size)
        coverage = coverage.union(before).union(after)
        requested = target
    }

    mutating func landed(at actual: CGRect, target: CGRect) {
        guard requested == target else { return }
        coverage = actual.approxEqual(target, tolerance: 1) ? actual : coverage.union(actual)
    }
}
