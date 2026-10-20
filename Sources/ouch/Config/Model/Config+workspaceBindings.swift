import AppKit

extension Config {
    var workspaceBindings: [KeyBinding] {
        guard virtualWorkspaces else { return bindings }
        var defaults = Config.parse("bind = CTRL, 1..0, workspace, 1..10\n"
            + "bind = CTRL, left|right, workspace, r-1|r+1\n"
            + "bind = CTRL SHIFT, 1..0, movetoworkspace, 1..10\n"
            + "bind = CTRL SHIFT, left|right, movetoworkspace, r-1|r+1").bindings
        let configured = Set(bindings.filter(\.submap.isEmpty).map { Hotkeys.key($0.keyCode, $0.mods) })
        defaults.removeAll { configured.contains(Hotkeys.key($0.keyCode, $0.mods)) }
        return defaults + bindings
    }
}
