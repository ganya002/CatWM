import AppKit

extension WindowActions {
    static let columnwidth = WindowAction.text(
        "columnwidth", "columns", "Change the width of the focused column",
        .text("width", "`cycle` (the next preset width), `max`, a change such as `+10` or `-10`, "
            + "or a width such as `50`, in percent of the screen"),
        pickers: [
            ActionPicker("Next Column Width", .columns, "cycle", "arrow.left.and.right"),
            ActionPicker("Maximize Column", .columns, "max", "arrow.up.left.and.arrow.down.right"),
            ActionPicker("Wider Column", .columns, "+10", "arrow.left.and.right.square", order: 1),
            ActionPicker("Narrower Column", .columns, "-10", "arrow.right.and.line.vertical.and.arrow.left", order: 1)
        ]
    ) { $0.manager.columnWidthCommand($0.arg) }

    static let windowheight = WindowAction.text(
        "windowheight", "columns", "Change the height of the focused window in its column",
        .text("change", "A change such as `+10` or `-10`, in percent of the column"),
        pickers: [
            ActionPicker("Taller Window", .columns, "+10", "arrow.up.and.down.square", order: 2),
            ActionPicker("Shorter Window", .columns, "-10", "arrow.down.and.line.horizontal.and.arrow.up", order: 2)
        ]
    ) { $0.manager.windowHeightCommand($0.arg) }

    static let centercolumn = WindowAction(
        name: "centercolumn", group: "columns", summary: "Scroll the focused column to the middle of the screen",
        pickers: [ActionPicker("Center Column", .columns, "", "align.horizontal.center")]
    ) { $0.manager.centerColumn() }

    static let consumeorexpel = WindowAction(
        name: "consumeorexpel", group: "columns",
        summary: "Move the focused window into the column next to it, or out of its column",
        args: [.choice("direction", ["left", "right"], "Direction")], argument: { $0.text("direction") },
        pickers: [Direction.left, .right].map {
            ActionPicker("Move Window Into or Out of Column \($0.title)", .columns, $0.rawValue,
                         "rectangle.split.1x2", group: "Into or Out of Column", short: $0.title)
        },
        run: { context in
            if let direction = Direction(context.arg) { context.manager.consumeOrExpel(direction) }
        }
    )

    static let togglecolumntabs = WindowAction(
        name: "togglecolumntabs", group: "columns", summary: "Show the windows of the focused column as tabs",
        pickers: [ActionPicker("Toggle Column Tabs", .columns, "", "rectangle.stack")]
    ) { $0.manager.toggleColumnTabs() }

    static let toggletiling = WindowAction(
        name: "toggletiling", group: "columns", summary: "Turn tiling on or off",
        pickers: [ActionPicker("Toggle Tiling", .app, "", "power")]
    ) { $0.manager.toggleTiling() }

    static let retile = WindowAction(
        name: "retile", group: "columns", summary: "Place every window again", aliases: ["reevaluate"],
        pickers: [ActionPicker("Retile Windows", .app, "", "arrow.clockwise")]
    ) { context in
        context.manager.corrections = [:]
        context.manager.refresh()
    }
}
