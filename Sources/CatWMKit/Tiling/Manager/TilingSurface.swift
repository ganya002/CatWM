import AppKit

package protocol TilingSurface {
    func start(_ manager: WindowManager)
    func apply(_ config: Config)

    func showHUD(_ text: String, layout: Layout?, on screen: NSScreen?)
    func warnHUD(_ text: String, on screen: NSScreen?)

    var inMode: Bool { get }
    func leaveMode()
    var keybindsActive: Bool { get }
    var keysPaused: Bool { get }
    func setKeyTap(enabled: Bool)
    func setKeyBinds(enabled: Bool)
    func stop()

    func tilesDidChange(instant: Bool)
    func splitSwapped(on screen: String)
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
    func toggleOverview()
    func undoOverview()
    func refreshed(_ screens: [Screen])
    func openSwitcher(backward: Bool)
    func focusChanged()
    func toggleFocusEffect(_ effect: FocusEffect)
    var loginItem: (enabled: Bool, needsApproval: Bool) { get }
    func preview(_ command: String, _ argument: String) -> Bool
}

extension TilingSurface {
    package func showHUD(_ text: String, on screen: NSScreen?) { showHUD(text, layout: nil, on: screen) }
}

package struct HeadlessSurface: TilingSurface {
    package func start(_: WindowManager) {}
    package func apply(_: Config) {}
    package func showHUD(_: String, layout _: Layout?, on _: NSScreen?) {}
    package func warnHUD(_: String, on _: NSScreen?) {}
    package var inMode: Bool { false }
    package func leaveMode() {}
    package var keybindsActive: Bool { false }
    package var keysPaused: Bool { false }
    package func setKeyTap(enabled _: Bool) {}
    package func setKeyBinds(enabled _: Bool) {}
    package func stop() {}
    package func tilesDidChange(instant _: Bool) {}
    package func splitSwapped(on _: String) {}
    package func tabsDidChange(instant _: Bool) {}
    package func batchTabChanges(_ changes: () -> Void) { changes() }
    package func restackTabStrips() {}
    package var revealedTabGroup: Int? { nil }
    package func previewTabDrop(_: Window, at _: CGPoint) -> Bool { false }
    package func endTabPreview(of _: CGWindowID) -> (group: Int, index: Int)? { nil }
    package var showsTabDrop: Bool { false }
    package func showTabDropHint(over _: CGRect, adding _: Window) {}
    package func hideTabDropHint() {}
    package func followTabStrip(_: Int, at _: CGVector, lowest _: CGFloat) {}
    package func endTabStripFollow() {}
    package var watchesTitles: Bool { false }
    package func titleChanged(_: Window) {}
    package func windowForgotten(_: CGWindowID) {}
    package func abandonOverview() {}
    package func toggleOverview() {}
    package func undoOverview() {}
    package func refreshed(_: [Screen]) {}
    package func openSwitcher(backward _: Bool) {}
    package func focusChanged() {}
    package func toggleFocusEffect(_: FocusEffect) {}
    package var loginItem: (enabled: Bool, needsApproval: Bool) { (false, false) }
    package func preview(_: String, _: String) -> Bool { false }
}
