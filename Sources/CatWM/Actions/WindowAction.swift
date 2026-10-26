import AppKit

struct ActionContext {
    let manager: WindowManager
    let arg: String
}

struct ActionPicker {
    let title: String
    let category: ActionCategory
    let args: String
    let symbol: String
    var group: String?
    var short: String?
    var focusRequired: FocusRequirement = .byCategory
    var order = 0

    init(_ title: String, _ category: ActionCategory, _ args: String, _ symbol: String, group: String? = nil,
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

struct WindowAction {
    let name: String
    let group: String
    let summary: String
    var args: [CommandArg] = []
    var access: CommandAccess = .public
    var aliases: [String] = []
    var argument: (Invocation) -> String = { _ in "" }
    var pickers: [ActionPicker] = []
    let run: (ActionContext) -> Void

    func action(for picker: ActionPicker) -> Action {
        Action(title: picker.title, category: picker.category, dispatcher: name, args: picker.args,
               symbol: picker.symbol, group: picker.group, short: picker.short, focusRequired: picker.focusRequired)
    }

    static func direction(_ name: String, _ group: String, _ summary: String, pickers: [ActionPicker] = [],
                          run: @escaping (ActionContext) -> Void) -> Self {
        Self(name: name, group: group, summary: summary,
             args: [.choice("direction", ["left", "right", "up", "down"], "Direction")],
             argument: { $0.text("direction") }, pickers: pickers, run: run)
    }

    static func step(_ name: String, _ group: String, _ summary: String, pickers: [ActionPicker] = [],
                     run: @escaping (ActionContext) -> Void) -> Self {
        Self(name: name, group: group, summary: summary,
             args: [.choice("step", ["next", "prev"], "Which way to go. The default is `next`.", required: false)],
             argument: { $0.text("step") }, pickers: pickers, run: run)
    }

    static func text(_ name: String, _ group: String, _ summary: String, _ arg: CommandArg,
                     access: CommandAccess = .public, aliases: [String] = [], pickers: [ActionPicker] = [],
                     run: @escaping (ActionContext) -> Void) -> Self {
        Self(name: name, group: group, summary: summary, args: [arg], access: access, aliases: aliases,
             argument: { $0.text(arg.name) }, pickers: pickers, run: run)
    }
}

extension ActionContext {
    var backward: Bool { arg.lowercased().hasPrefix("prev") }
    var tabBackward: Bool { backward || arg.lowercased().hasPrefix("b") }
}

enum WindowActions {
    static let all: [WindowAction] = [
        movefocus, cyclenext, focusmonitor, movewindow, movewindowtomonitor, swapwindow, swapnext,
        togglefloating, fullscreen, nativefullscreen, minimize, killactive,
        moveintogroup, moveoutofgroup, changegroupactive, movegroupwindow,
        columnwidth, windowheight, centercolumn, consumeorexpel, togglecolumntabs, toggletiling, retile,
        workspace, movetoworkspace, movetoworkspacesilent, sethomespace,
        sort, sortUndo, switcher,
        submap, reload, exit, exec, launch
    ]

    private static let byName = Dictionary(uniqueKeysWithValues: all.flatMap { action in
        ([action.name] + action.aliases).map { ($0, action) }
    })

    static func named(_ name: String) -> WindowAction? { byName[name] }
}
