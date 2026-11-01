import AppKit

extension CommandRegistry {
    private static let rect = "rect"

    static let state: [Command] = [
        Command(name: "status", group: "state", summary: "Read the state of CatWM", result: .object([
            Field(name: "trusted", type: "bool", summary: "Accessibility permission is granted"),
            Field(name: "keybindsActive", type: "bool", summary: "The key tap works"),
            Field(name: "running", type: "bool", summary: "The window manager runs"),
            Field(name: "tilingEnabled", type: "bool", summary: "Tiling is on"),
            Field(name: "launchAtLogin", type: "bool", summary: "CatWM opens at login"),
            Field(name: "loginNeedsApproval", type: "bool", summary: "The login item needs approval"),
            Field(name: "inputMonitoring", type: "bool", summary: "Input Monitoring permission is granted"),
            Field(name: "tiled", type: "int", summary: "Number of tiled windows"),
            Field(name: "floating", type: "int", summary: "Number of floating windows"),
            Field(name: "mode", type: "string", summary: "Active key mode, empty for none"),
            Field(name: "workspaces", type: "string", summary: "`catwm` or `macos`"),
            Field(name: "screens", type: "object[]", summary: "One entry for each display")
        ])) { call in call.manager.statusJSON() },
        Command(name: "windows", group: "state", summary: "List the windows that CatWM knows", result: .list([
            Field(name: "id", type: "int", summary: "Window ID"),
            Field(name: "pid", type: "int", summary: "Process ID"),
            Field(name: "app", type: "string?", summary: "Bundle ID"),
            Field(name: "title", type: "string?", summary: "Window title"),
            Field(name: "focused", type: "bool", summary: "The window has focus"),
            Field(name: "floating", type: "bool", summary: "The window floats"),
            Field(name: "minimized", type: "bool", summary: "The window is minimised"),
            Field(name: "fullscreen", type: "bool", summary: "The window is in full screen"),
            Field(name: "visible", type: "bool", summary: "The window is on a shown workspace"),
            Field(name: "workspace", type: "string?", summary: "Workspace name"),
            Field(name: "screen", type: "string?", summary: "Display ID"),
            Field(name: "frame", type: rect + "?", summary: "Last known frame")
        ])) { call in call.manager.windowsJSON() },
        Command(name: "workspaces", group: "state", summary: "List the workspaces, including empty Desktops",
                result: .list([
            Field(name: "name", type: "string", summary: "Workspace name"),
            Field(name: "windows", type: "int[]", summary: "Window IDs in the workspace"),
            Field(name: "screens", type: "string[]", summary: "Displays that show the workspace"),
            Field(name: "native", type: "bool", summary: "The workspace is a macOS Desktop")
        ])) { call in call.manager.workspacesJSON() },
        Command(name: "screens", group: "state", summary: "List the displays", result: .list([
            Field(name: "uuid", type: "string", summary: "Display ID"),
            Field(name: "name", type: "string", summary: "Display name"),
            Field(name: "frame", type: rect, summary: "Display frame"),
            Field(name: "usable", type: rect, summary: "Area for tiled windows"),
            Field(name: "layout", type: "string", summary: "Layout name"),
            Field(name: "ratio", type: "number", summary: "Main pane ratio"),
            Field(name: "mainCount", type: "int", summary: "Number of main windows"),
            Field(name: "workspace", type: "string", summary: "Workspace shown on the display"),
            Field(name: "focused", type: "bool", summary: "The display has focus")
        ])) { call in call.manager.screensJSON() },
        Command(name: "dump", group: "state", summary: "Read a text report of the tiling state",
                result: .text) { call in
            let lines = call.manager.dumpLines()
            lines.forEach { Log.info($0) }
            return .string(lines.joined(separator: "\n"))
        }
    ]

    static let config: [Command] = [
        Command(name: "config.get", group: "config", summary: "Read the value of a config option",
                args: [.text("key", "Option name")], result: .text) { call in
            guard let option = ConfigOption.named(call.text("key")) else {
                throw ControlError.invalid("Unknown option `\(call.text("key"))`")
            }
            return .string(option.text(call.manager.config))
        },
        Command(name: "config.set", group: "config", summary: "Change a config option and reload the config",
                args: [.text("key", "Option name"), .text("value", "New value")]) { call in
            guard let option = ConfigOption.named(call.text("key")) else {
                throw ControlError.invalid("Unknown option `\(call.text("key"))`")
            }
            let value = call.text("value")
            guard !value.contains(where: \.isNewline) else {
                throw ControlError.invalid("`value` must be one line")
            }
            var probe = Config()
            if let problem = option.read(&probe, value, call.text("key")) {
                throw ControlError.invalid(problem)
            }
            do {
                try Config.write(option: option.key, value)
            } catch {
                throw ControlError.failed("Could not save config: \(error.localizedDescription)")
            }
            call.manager.reload(showHUD: false)
            return .null
        },
        Command(name: "config.options", group: "config", summary: "List the config options", result: .list([
            Field(name: "key", type: "string", summary: "Option name"),
            Field(name: "value", type: "string", summary: "Current value"),
            Field(name: "default", type: "string", summary: "Default value"),
            Field(name: "type", type: "string", summary: "Accepted values"),
            Field(name: "summary", type: "string", summary: "What the option does")
        ])) { call in
            let current = call.manager.config
            return .array(Options.all.map { option in
                ["key": .string(option.key), "value": .string(option.text(current)),
                 "default": .string(option.defaultText), "type": .string(option.valueDescription),
                 "summary": .string(option.documentation)]
            })
        }
    ]
}
