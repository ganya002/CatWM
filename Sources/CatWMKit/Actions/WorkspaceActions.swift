import AppKit

extension WindowActions {
    package static let workspace = WindowAction.text(
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

    package static let movetoworkspace = WindowAction.text(
        "movetoworkspace", "workspaces", "Move the focused window to a workspace and go there",
        .text("workspace", "Same values as `workspace`"),
        pickers: (1...10).map {
            ActionPicker("Move Window to Workspace \($0)", .spaces, "\($0)", "\($0).square.fill",
                         group: "Move Window to Workspace", short: "Workspace \($0)", focusRequired: true)
        }
    ) { $0.manager.moveToWorkspaceCommand($0.arg, follow: true) }

    package static let movetoworkspacesilent = WindowAction.text(
        "movetoworkspacesilent", "workspaces", "Move the focused window to a workspace and stay",
        .text("workspace", "Same values as `workspace`"),
        pickers: (1...10).map {
            ActionPicker("Send Window to Workspace \($0)", .spaces, "\($0)", "\($0).square.fill",
                         group: "Send Window to Workspace", short: "Workspace \($0)", focusRequired: true)
        }
    ) { $0.manager.moveToWorkspaceCommand($0.arg, follow: false) }

    package static let sethomespace = WindowAction(
        name: "sethomespace", group: "workspaces", summary: "Make the current Desktop the home Desktop"
    ) { $0.manager.makeCurrentSpaceHome() }

    package static let sort = WindowAction(
        name: "sort", group: "overview", summary: "Open or close the Overview",
        pickers: [ActionPicker("Overview", .window, "", "square.grid.3x1.below.line.grid.1x2", focusRequired: false)]
    ) { $0.manager.surface.toggleOverview() }

    package static let sortUndo = WindowAction(
        name: "sort-undo", group: "overview", summary: "Undo the last Overview change",
        pickers: [ActionPicker("Undo Last Overview Change", .window, "", "arrow.uturn.backward", focusRequired: false,
                               order: 1)]
    ) { $0.manager.surface.undoOverview() }

    package static let switcher = WindowAction.step(
        "switcher", "overview", "Open the window switcher",
        pickers: [
            ActionPicker("Switch Windows", .window, "", "rectangle.stack", focusRequired: false),
            ActionPicker("Switch Windows Backward", .window, "prev", "rectangle.stack", focusRequired: false)
        ]
    ) { $0.manager.surface.openSwitcher(backward: $0.backward) }
}
