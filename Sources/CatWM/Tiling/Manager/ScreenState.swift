import AppKit

final class ScreenState {
    var layout: Layout
    var ratio: CGFloat = 0.5
    var mainCount = 1
    var zoomed: CGWindowID?
    init(layout: Layout) { self.layout = layout }

    func copy() -> ScreenState {
        let clone = ScreenState(layout: layout)
        clone.ratio = ratio; clone.mainCount = mainCount; clone.zoomed = zoomed
        return clone
    }
}
