import AppKit

package struct ActionContext {
    package let manager: WindowManager
    package let arg: String
    package var target: Window?
    @MainActor package var window: Window? { target ?? manager.focusedWindow() }
}

package struct ActionPicker: Sendable {
    package let title: String
    package let category: ActionCategory
    package let args: String
    package let symbol: String
    package var group: String?
    package var short: String?
    package var focusRequired: FocusRequirement = .byCategory
    package var order = 0

    package init(_ title: String, _ category: ActionCategory, _ args: String, _ symbol: String, group: String? = nil,
                 short: String? = nil, focusRequired: FocusRequirement = .byCategory, order: Int = 0) {
        self.title = title
        self.category = category
        self.args = args
        self.symbol = symbol
        self.group = group
        self.short = short
        self.focusRequired = focusRequired
        self.order = order
    }
}

package struct WindowAction: Sendable {
    package let name: String
    package let group: String
    package let summary: String
    package var args: [CommandArg] = []
    var access: CommandAccess = .public
    package var aliases: [String] = []
    package var argument: @Sendable (Invocation) -> String = { _ in "" }
    package var pickers: [ActionPicker] = []
    package var takesWindow = false
    package let run: @MainActor @Sendable (ActionContext) -> Void

    package func targetingWindow() -> Self {
        var action = self
        action.takesWindow = true
        return action
    }

    package func action(for picker: ActionPicker) -> Action {
        Action(title: picker.title, category: picker.category, dispatcher: name, args: picker.args,
               symbol: picker.symbol, group: picker.group, short: picker.short, focusRequired: picker.focusRequired)
    }

    package static func direction(_ name: String, _ group: String, _ summary: String, pickers: [ActionPicker] = [],
                                  run: @escaping @MainActor @Sendable (ActionContext) -> Void) -> Self {
        Self(name: name, group: group, summary: summary,
             args: [.choice("direction", ["left", "right", "up", "down"], "Direction")],
             argument: { $0.text("direction") }, pickers: pickers, run: run)
    }

    package static func step(_ name: String, _ group: String, _ summary: String, pickers: [ActionPicker] = [],
                             run: @escaping @MainActor @Sendable (ActionContext) -> Void) -> Self {
        Self(name: name, group: group, summary: summary,
             args: [.choice("step", ["next", "prev"], "Which way to go. The default is `next`.", required: false)],
             argument: { $0.text("step") }, pickers: pickers, run: run)
    }

    package static func text(_ name: String, _ group: String, _ summary: String, _ arg: CommandArg,
                             access: CommandAccess = .public, aliases: [String] = [], pickers: [ActionPicker] = [],
                             run: @escaping @MainActor @Sendable (ActionContext) -> Void) -> Self {
        Self(name: name, group: group, summary: summary, args: [arg], access: access, aliases: aliases,
             argument: { $0.text(arg.name) }, pickers: pickers, run: run)
    }
}

extension ActionContext {
    package var backward: Bool { arg.lowercased().hasPrefix("prev") }
    package var tabBackward: Bool { backward || arg.lowercased().hasPrefix("b") }

    var deltaPair: CGSize? {
        let parts = arg.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]), x.isFinite, y.isFinite else {
            return nil
        }
        return CGSize(width: x, height: y)
    }

    var exactPair: CGPoint? {
        let parts = arg.lowercased().split(whereSeparator: \.isWhitespace)
        guard parts.count == 3, parts[0] == "exact", let x = Double(parts[1]), let y = Double(parts[2]),
              x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }
}

package enum WindowActions {
    package static let all: [WindowAction] = [
        movefocus, cyclenext, focusmonitor, movewindow, movewindowtomonitor, swapwindow, swapnext,
        togglefloating, setfloating, settiled, resizeactive, moveactive, centerwindow, pseudo, pin,
        fullscreen, nativefullscreen, minimize, killactive,
        moveintogroup, moveoutofgroup, changegroupactive, movegroupwindow, togglegroup, lockactivegroup,
        layoutmsg, splitratio, cyclelayout, layout, toggletiling, retile,
        workspace, movetoworkspace, movetoworkspacesilent, togglespecialworkspace, sethomespace,
        sort, sortUndo, switcher,
        submap, reload, exit, exec, launch
    ]

    private static let byName = Dictionary(uniqueKeysWithValues: all.flatMap { action in
        ([action.name] + action.aliases).map { ($0, action) }
    })

    package static func named(_ name: String) -> WindowAction? { byName[name] }
}
