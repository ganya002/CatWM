import AppKit

extension WindowActions {
    private static let displayTarget = CommandArg.text(
        "target", "`+1`, `-1`, `left`, `right`, `up`, `down` or a display number counting from 0")

    static let movefocus = WindowAction.direction(
        "movefocus", "focus", "Focus the window next to the focused window",
        pickers: Direction.allCases.map {
            ActionPicker("Focus \($0.title)", .focus, $0.rawValue, "arrow.\($0.symbolName)")
        }
    ) { context in
        if let direction = Direction(context.arg) { context.manager.moveFocus(direction) }
    }

    static let cyclenext = WindowAction.step(
        "cyclenext", "focus", "Focus the next or previous window",
        pickers: [
            ActionPicker("Focus Next Window", .focus, "", "arrow.forward"),
            ActionPicker("Focus Previous Window", .focus, "prev", "arrow.backward")
        ]
    ) { $0.manager.cycleFocus($0.backward ? -1 : 1) }

    static let focusmonitor = WindowAction.text(
        "focusmonitor", "displays", "Focus a display", displayTarget,
        pickers: [
            ActionPicker("Focus Next Display", .displays, "+1", "display"),
            ActionPicker("Focus Previous Display", .displays, "-1", "display")
        ] + Direction.allCases.enumerated().map { index, direction in
            ActionPicker("Focus Display \(direction.title)", .displays, direction.rawValue,
                         "arrow.\(direction.symbolName).to.line", order: index + 1)
        }
    ) { $0.manager.focusMonitor($0.arg) }

    static let movewindowtomonitor = WindowAction.text(
        "movewindowtomonitor", "displays", "Move the focused window to another display", displayTarget
    ) { $0.manager.moveToMonitor($0.arg) }

    static let movewindow = WindowAction.direction(
        "movewindow", "window", "Move the focused window in a direction",
        pickers: Direction.allCases.map {
            ActionPicker("Move Window \($0.title)", .move, $0.rawValue, "arrow.\($0.symbolName).square")
        } + [
            ActionPicker("Move Window to Previous Display", .displays, "mon:-1", "rectangle.portrait.and.arrow.right",
                         focusRequired: true)
        ] + Direction.allCases.enumerated().map { index, direction in
            ActionPicker("Move Window to Display \(direction.title)", .displays, "mon:\(direction.rawValue)",
                         "arrow.\(direction.symbolName).square", focusRequired: true, order: index + 1)
        }
    ) { $0.manager.moveWindowCommand($0.arg) }

    static let swapwindow = WindowAction.direction(
        "swapwindow", "window", "Swap the focused window with its neighbour"
    ) { $0.manager.moveWindowCommand($0.arg) }

    static let swapnext = WindowAction.step(
        "swapnext", "window", "Swap the focused window with the next or previous window",
        pickers: [
            ActionPicker("Swap With Next Window", .move, "", "arrow.left.arrow.right"),
            ActionPicker("Swap With Previous Window", .move, "prev", "arrow.right.arrow.left", order: 1)
        ]
    ) { $0.manager.cycleSwap($0.backward ? -1 : 1) }

    static let togglefloating = WindowAction(
        name: "togglefloating", group: "window", summary: "Float or tile the focused window"
    ) { $0.manager.toggleFloating() }

    static let fullscreen = WindowAction(
        name: "fullscreen", group: "window", summary: "Fill the screen with the focused window, inside the tiling"
    ) { $0.manager.toggleZoom() }

    static let nativefullscreen = WindowAction(
        name: "nativefullscreen", group: "window", summary: "Give the focused window a macOS full screen Desktop"
    ) { $0.manager.toggleNativeFullscreen() }

    static let minimize = WindowAction(
        name: "minimize", group: "window", summary: "Minimise the focused window"
    ) { context in
        if let window = context.manager.focusedWindow() { context.manager.minimize(window) }
    }

    static let killactive = WindowAction(
        name: "killactive", group: "window", summary: "Close the focused window"
    ) { context in
        let manager = context.manager
        manager.closeAndSort.lastClose = Date()
        _ = manager.focusedWindow().map { manager.closeWindow($0.id) }
    }

    static let moveintogroup = WindowAction.direction(
        "moveintogroup", "tabs", "Add the focused window to the tabs of its neighbour",
        pickers: Direction.allCases.map {
            ActionPicker("Add Window to Tabs \($0.title)", .move, $0.rawValue, "rectangle.stack.badge.plus",
                         group: "Add Window to Tabs", short: $0.title)
        }
    ) { context in
        let manager = context.manager
        guard let window = manager.focusedWindow(), let direction = Direction(context.arg), !window.isFloating else {
            return
        }
        let candidates = manager.order.filter {
            manager.visible.contains($0) && !manager.tabs.isBehind($0) && $0 != window.id
        }.compactMap { manager.windows[$0] }.filter { !$0.isFloating }
        guard case let .window(host) = manager.resolve(direction, from: window, among: candidates) else { return }
        manager.joinTab(window.id, onto: host.id)
    }

    static let moveoutofgroup = WindowAction(
        name: "moveoutofgroup", group: "tabs", summary: "Take the focused window out of its tabs",
        pickers: [ActionPicker("Remove Window From Tabs", .move, "", "rectangle.stack.badge.minus")]
    ) { context in
        if let window = context.manager.focusedWindow() { context.manager.untab(window.id) }
    }

    static let changegroupactive = WindowAction.text(
        "changegroupactive", "tabs", "Show another tab",
        .text("tab", "`next`, `prev` or a tab number counting from 1", required: false),
        pickers: [
            ActionPicker("Next Tab", .focus, "f", "chevron.right.2", order: 1),
            ActionPicker("Previous Tab", .focus, "b", "chevron.left.2", order: 1)
        ]
    ) { context in
        let manager = context.manager
        guard let window = manager.focusedWindow() else { return }
        let lowered = context.arg.lowercased()
        if let index = Int(lowered), let members = manager.tabs.group(of: window.id)?.members,
           members.indices.contains(index - 1) {
            manager.selectTab(members[index - 1])
        } else if let next = manager.tabs.neighbor(of: window.id, offset: context.tabBackward ? -1 : 1) {
            manager.selectTab(next)
        }
    }

    static let movegroupwindow = WindowAction.step(
        "movegroupwindow", "tabs", "Move the focused tab along the strip",
        pickers: [
            ActionPicker("Move Tab Right", .move, "f", "arrow.right.to.line"),
            ActionPicker("Move Tab Left", .move, "b", "arrow.left.to.line")
        ]
    ) { context in
        guard let window = context.manager.focusedWindow() else { return }
        context.manager.moveTab(window.id, by: context.tabBackward ? -1 : 1)
    }
}
