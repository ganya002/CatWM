import AppKit

extension WindowManager {
    struct ScreenStatus: Equatable {
        var uuid: String
        var name: String
        var layout: Layout
        var workspace: String
    }

    struct Status: Equatable {
        var trusted: Bool
        var keybindsActive: Bool
        var running: Bool
        var tilingEnabled: Bool
        var launchAtLogin: Bool
        var loginNeedsApproval: Bool
        var inputMonitoring: Bool
        var tiled: Int
        var floating: Int
        var screens: [ScreenStatus]
    }
}
