import AppKit

final class ScreenState {
    var layout: Layout
    var ratio: CGFloat = 0.5
    var mainCount = 1
    var zoomed: CGWindowID?
    init(layout: Layout) { self.layout = layout }

    func copy() -> ScreenState {
        let c = ScreenState(layout: layout)
        c.ratio = ratio; c.mainCount = mainCount; c.zoomed = zoomed
        return c
    }
}
