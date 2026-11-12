import AppKit

extension WindowActions {
    package static let layoutmsg = WindowAction.text(
        "layoutmsg", "layout", "Send a message to the layout",
        .text("message", "`swapwithmaster`, `swapsides`, `focusmaster`, `addmaster`, `removemaster`, "
            + "`mfact <value>`, `orientationnext`, `orientationprev`, or in the dwindle layout `togglesplit` and "
            + "`swapsplit`"),
        pickers: [
            ActionPicker("Focus Main Window", .focus, "focusmaster", "star"),
            ActionPicker("Swap Sides", .layout, "swapsides", "arrow.left.arrow.right.square"),
            ActionPicker("More Main Windows", .layout, "addmaster", "plus.rectangle"),
            ActionPicker("Fewer Main Windows", .layout, "removemaster", "minus.rectangle")
        ]
    ) { $0.manager.layoutMessage($0.arg) }

    package static let splitratio = WindowAction.text(
        "splitratio", "layout", "Change the size of the main pane",
        .text("value", "A change such as `+0.05` or `-0.05`, or `exact 0.6`"),
        pickers: [
            ActionPicker("Grow Main Pane", .layout, "+0.05", "arrow.left.and.right.square", order: -1),
            ActionPicker("Shrink Main Pane", .layout, "-0.05", "arrow.right.and.line.vertical.and.arrow.left",
                         order: -1)
        ]
    ) { $0.manager.adjustRatio($0.arg) }

    package static let cyclelayout = WindowAction.step(
        "cyclelayout", "layout", "Use the next or previous layout",
        pickers: [ActionPicker("Previous Layout", .layout, "prev", "rectangle.2.swap", order: -2)]
    ) { $0.manager.cycleLayout($0.backward ? -1 : 1) }

    package static let layout = WindowAction.text(
        "layout", "layout", "Use a layout on the current screen",
        .choice("layout", Layout.allCases.map(\.rawValue), "Layout name"), aliases: ["setlayout"],
        pickers: Layout.allCases.map {
            ActionPicker("Use \($0.title) Layout", .layout, $0.rawValue, "rectangle.split.2x2", group: "Use Layout",
                         short: $0.title)
        }
    ) { $0.manager.setLayoutCommand($0.arg) }

    package static let toggletiling = WindowAction(
        name: "toggletiling", group: "layout", summary: "Turn tiling on or off",
        pickers: [ActionPicker("Toggle Tiling", .app, "", "power")]
    ) { $0.manager.toggleTiling() }

    package static let retile = WindowAction(
        name: "retile", group: "layout", summary: "Place every window again", aliases: ["reevaluate"],
        pickers: [ActionPicker("Retile Windows", .app, "", "arrow.clockwise")]
    ) { context in
        context.manager.corrections = [:]
        context.manager.refresh()
    }
}
