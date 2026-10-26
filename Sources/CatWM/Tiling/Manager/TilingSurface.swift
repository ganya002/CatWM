import AppKit

protocol TilingSurface {
    func start(_ manager: WindowManager)
    func apply(_ config: Config)

    func showHUD(_ text: String, on screen: NSScreen?)
    func warnHUD(_ text: String, on screen: NSScreen?)

    var inMode: Bool { get }
    func leaveMode()
    var keybindsActive: Bool { get }
    var keysPaused: Bool { get }
    func setKeyTap(enabled: Bool)

    func tilesDidChange(instant: Bool)
    func tabsDidChange(instant: Bool)
    func batchTabChanges(_ changes: () -> Void)
    func restackTabStrips()
    var revealedTabGroup: Int? { get }
    func previewTabDrop(_ window: Window, at point: CGPoint) -> Bool
    func endTabPreview(of id: CGWindowID) -> (group: Int, index: Int)?
    var showsTabDrop: Bool { get }
    func showTabDropHint(over rect: CGRect, adding window: Window)
    func hideTabDropHint()
    func followTabStrip(_ group: Int, at offset: CGVector, lowest: CGFloat)
    func endTabStripFollow()

    var watchesTitles: Bool { get }
    func titleChanged(_ window: Window)
    func windowForgotten(_ id: CGWindowID)

    func abandonOverview()
}

extension TilingSurface {
}

struct HeadlessSurface: TilingSurface {
    func start(_: WindowManager) {}
    func apply(_: Config) {}
    func showHUD(_: String, on _: NSScreen?) {}
    func warnHUD(_: String, on _: NSScreen?) {}
    var inMode: Bool { false }
    func leaveMode() {}
    var keybindsActive: Bool { false }
    var keysPaused: Bool { false }
    func setKeyTap(enabled _: Bool) {}
    func tilesDidChange(instant _: Bool) {}
    func tabsDidChange(instant _: Bool) {}
    func batchTabChanges(_ changes: () -> Void) { changes() }
    func restackTabStrips() {}
    var revealedTabGroup: Int? { nil }
    func previewTabDrop(_: Window, at _: CGPoint) -> Bool { false }
    func endTabPreview(of _: CGWindowID) -> (group: Int, index: Int)? { nil }
    var showsTabDrop: Bool { false }
    func showTabDropHint(over _: CGRect, adding _: Window) {}
    func hideTabDropHint() {}
    func followTabStrip(_: Int, at _: CGVector, lowest _: CGFloat) {}
    func endTabStripFollow() {}
    var watchesTitles: Bool { false }
    func titleChanged(_: Window) {}
    func windowForgotten(_: CGWindowID) {}
    func abandonOverview() {}
}
