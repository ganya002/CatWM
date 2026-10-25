import AppKit

extension CommandRegistry {
    private static let directions = ["left", "right", "up", "down"]
    private static let steps = ["next", "prev"]

    private static func dispatcher(_ name: String, _ group: String, _ summary: String, args: [CommandArg] = [],
                                   access: CommandAccess = .public,
                                   argument: @escaping (Invocation) -> String = { _ in "" }) -> Command {
        Command(name: name, group: group, summary: summary, args: args, access: access) { call in
            WindowManager.shared.dispatch(name, argument(call))
            return .null
        }
    }

    private static func direction(_ name: String, _ group: String, _ summary: String) -> Command {
        dispatcher(name, group, summary, args: [.choice("direction", directions, "Direction")]) { $0.text("direction") }
    }

    private static func step(_ name: String, _ group: String, _ summary: String) -> Command {
        dispatcher(name, group, summary, args: [.choice("step", steps, "Which way to go. The default is `next`.",
                                                        required: false)]) { $0.text("step") }
    }

    static let dispatchers: [Command] = [
        direction("movefocus", "focus", "Focus the window next to the focused window"),
        step("cyclenext", "focus", "Focus the next or previous window"),
        dispatcher("focusmonitor", "displays", "Focus a display", args: [
            .text("target", "`+1`, `-1`, `left`, `right`, `up`, `down` or a display number counting from 0")
        ]) { $0.text("target") },
        direction("movewindow", "window", "Move the focused window in a direction"),
        dispatcher("movewindowtomonitor", "displays", "Move the focused window to another display", args: [
            .text("target", "`+1`, `-1`, `left`, `right`, `up`, `down` or a display number counting from 0")
        ]) { $0.text("target") },
        direction("swapwindow", "window", "Swap the focused window with its neighbour"),
        step("swapnext", "window", "Swap the focused window with the next or previous window"),
        dispatcher("togglefloating", "window", "Float or tile the focused window"),
        dispatcher("fullscreen", "window", "Fill the screen with the focused window, inside the tiling"),
        dispatcher("nativefullscreen", "window", "Give the focused window a macOS full screen Desktop"),
        dispatcher("minimize", "window", "Minimise the focused window"),
        dispatcher("killactive", "window", "Close the focused window"),
        direction("moveintogroup", "tabs", "Add the focused window to the tabs of its neighbour"),
        dispatcher("moveoutofgroup", "tabs", "Take the focused window out of its tabs"),
        dispatcher("changegroupactive", "tabs", "Show another tab", args: [
            .text("tab", "`next`, `prev` or a tab number counting from 1", required: false)
        ]) { $0.text("tab") },
        step("movegroupwindow", "tabs", "Move the focused tab along the strip"),
        dispatcher("layoutmsg", "layout", "Send a message to the layout", args: [
            .text("message", "`swapwithmaster`, `swapsides`, `focusmaster`, `addmaster`, `removemaster`, "
                + "`mfact <value>`, `orientationnext` or `orientationprev`")
        ]) { $0.text("message") },
        dispatcher("splitratio", "layout", "Change the size of the main pane", args: [
            .text("value", "A change such as `+0.05` or `-0.05`, or `exact 0.6`")
        ]) { $0.text("value") },
        step("cyclelayout", "layout", "Use the next or previous layout"),
        dispatcher("layout", "layout", "Use a layout on the current screen", args: [
            .choice("layout", Layout.allCases.map(\.rawValue), "Layout name")
        ]) { $0.text("layout") },
        dispatcher("toggletiling", "layout", "Turn tiling on or off"),
        dispatcher("retile", "layout", "Place every window again"),
        dispatcher("workspace", "workspaces", "Show a workspace", args: [
            .text("workspace", "A number, a name (`name:<text>`), `previous`, `+1`, `-1` or `e+1` for the next "
                + "workspace with windows")
        ]) { $0.text("workspace") },
        dispatcher("movetoworkspace", "workspaces", "Move the focused window to a workspace and go there", args: [
            .text("workspace", "Same values as `workspace`")
        ]) { $0.text("workspace") },
        dispatcher("movetoworkspacesilent", "workspaces", "Move the focused window to a workspace and stay", args: [
            .text("workspace", "Same values as `workspace`")
        ]) { $0.text("workspace") },
        dispatcher("sethomespace", "workspaces", "Make the current Desktop the home Desktop"),
        dispatcher("sort", "overview", "Open or close the Overview"),
        dispatcher("sort-undo", "overview", "Undo the last Overview change"),
        step("switcher", "overview", "Open the window switcher"),
        dispatcher("submap", "app", "Enter a key mode, or leave it", args: [
            .text("name", "The mode name, or `reset` to leave the mode")
        ]) { $0.text("name") },
        dispatcher("reload", "app", "Read the config file again"),
        dispatcher("exit", "app", "Quit CatWM"),
        dispatcher("exec", "app", "Run a shell command", access: .keybindOnly),
        dispatcher("launch", "app", "Open an app, file, URL or command", access: .keybindOnly)
    ] + FocusDim.features.map { feature in
        dispatcher(feature.pointer.dispatcher, "focus", feature.pointer.action.title)
    }

    static let keybindOnly: Set<String> = Set(dispatchers.filter { $0.access == .keybindOnly }.map(\.name))
}
