import AppKit

extension WindowActions {
    static let workspace = WindowAction.text(
        "workspace", "workspaces", "Show a workspace",
        .text("workspace", "A number, a name (`name:<text>`), `previous`, `+1`, `-1` or `e+1` for the next "
            + "workspace with windows"),
        pickers: (1...10).map {
            ActionPicker("Workspace \($0)", .spaces, "\($0)", "\($0).square", group: "Go to Workspace",
                         short: "Workspace \($0)")
        } + [
            ActionPicker("Previous Workspace", .spaces, "previous", "arrow.uturn.backward.square"),
            ActionPicker("Next Workspace", .spaces, "+1", "chevron.right.square"),
            ActionPicker("Previous Numbered Workspace", .spaces, "-1", "chevron.left.square"),
            ActionPicker("Next Workspace With Windows", .spaces, "e+1", "chevron.forward.2")
        ]
    ) { $0.manager.showWorkspaceCommand($0.arg) }

    static let movetoworkspace = WindowAction.text(
        "movetoworkspace", "workspaces", "Move the focused window to a workspace and go there",
        .text("workspace", "Same values as `workspace`"),
        pickers: (1...10).map {
            ActionPicker("Move Window to Workspace \($0)", .spaces, "\($0)", "\($0).square.fill",
                         group: "Move Window to Workspace", short: "Workspace \($0)", focusRequired: true)
        }
    ) { $0.manager.moveToWorkspaceCommand($0.arg, follow: true) }

    static let movetoworkspacesilent = WindowAction.text(
        "movetoworkspacesilent", "workspaces", "Move the focused window to a workspace and stay",
        .text("workspace", "Same values as `workspace`"),
        pickers: (1...10).map {
            ActionPicker("Send Window to Workspace \($0)", .spaces, "\($0)", "\($0).square.fill",
                         group: "Send Window to Workspace", short: "Workspace \($0)", focusRequired: true)
        }
    ) { $0.manager.moveToWorkspaceCommand($0.arg, follow: false) }

    static let sethomespace = WindowAction(
        name: "sethomespace", group: "workspaces", summary: "Make the current Desktop the home Desktop"
    ) { $0.manager.makeCurrentSpaceHome() }

    static let sort = WindowAction(
        name: "sort", group: "overview", summary: "Open or close the Overview",
        pickers: [ActionPicker("Overview", .window, "", "square.grid.3x1.below.line.grid.1x2", focusRequired: false)]
    ) { $0.manager.toggleSortCommand() }

    static let sortUndo = WindowAction(
        name: "sort-undo", group: "overview", summary: "Undo the last Overview change",
        pickers: [ActionPicker("Undo Last Overview Change", .window, "", "arrow.uturn.backward", focusRequired: false,
                               order: 1)]
    ) { _ in SortPanel.shared.undoApplied() }

    static let switcher = WindowAction.text(
        "switcher", "overview", "Open the window switcher, or run a switcher key while it is open",
        .choice("key", SwitcherKey.allCases.map(\.rawValue),
                "`next` and `prev` open the switcher or move the selection. The others work while it is open. "
                    + "The default is `next`.", required: false),
        pickers: [
            ActionPicker("Switch Windows", .window, "", "rectangle.stack", focusRequired: false),
            ActionPicker("Switch Windows Backward", .window, "prev", "rectangle.stack", focusRequired: false),
            ActionPicker("Peek at the Window", .window, "peek", "eye", focusRequired: false, order: 1),
            ActionPicker("Show Only This App", .window, "app", "app", focusRequired: false, order: 1),
            ActionPicker("Change the Scope", .window, "scope", "scope", focusRequired: false, order: 1),
            ActionPicker("Bring the Window Here", .window, "bring", "arrow.down.to.line", focusRequired: false,
                         order: 1),
            ActionPicker("Minimize the Window", .window, "minimize", "minus.square", focusRequired: false, order: 1),
            ActionPicker("Close the Window", .window, "close", "xmark.square", focusRequired: false, order: 1),
            ActionPicker("Quit the App", .window, "quit", "power", focusRequired: false, order: 1),
            ActionPicker("Hide the App", .window, "hide", "eye.slash", focusRequired: false, order: 1),
            ActionPicker("Open the Window", .window, "pick", "return", focusRequired: false, order: 1),
            ActionPicker("Close the Switcher", .window, "cancel", "escape", focusRequired: false, order: 1)
        ]
    ) { Switcher.shared.run($0.arg) }
}
