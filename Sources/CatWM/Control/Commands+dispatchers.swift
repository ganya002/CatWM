import AppKit

extension CommandRegistry {
    static let dispatchers: [Command] = WindowActions.all.map { action in
        Command(name: action.name, group: action.group, summary: action.summary, args: action.args,
                access: action.access) { call in
            WindowManager.shared.dispatch(action.name, action.argument(call))
            return .null
        }
    } + FocusDim.features.map { feature in
        let name = feature.pointer.dispatcher
        return Command(name: name, group: "focus", summary: feature.pointer.action.title) { _ in
            WindowManager.shared.dispatch(name, "")
            return .null
        }
    }

    static let dispatcherNames: Set<String> = Set(dispatchers.map(\.name) + WindowActions.all.flatMap(\.aliases))

    static let keybindOnly: Set<String> = Set(dispatchers.filter { $0.access == .keybindOnly }.map(\.name))
}
