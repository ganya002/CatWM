import AppKit

extension WindowManager {

    struct Status {
        var trusted: Bool
        var keybindsActive: Bool
        var running: Bool
        var tilingEnabled: Bool
        var launchAtLogin: Bool
        var loginNeedsApproval: Bool
        var inputMonitoring: Bool
        var tiled: Int
        var floating: Int
        var screens: [(uuid: String, name: String, layout: Layout, workspace: String)]
    }

}
