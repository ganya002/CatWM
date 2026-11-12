import AppKit

extension CommandRegistry {
    private static let windowArg = CommandArg(
        name: "window", kind: .int, summary: "The id of the window to act on. The default is the focused window.",
        required: false)

    package static let dispatchers: [Command] = WindowActions.all.map { action in
        Command(name: action.name, group: action.group, summary: action.summary,
                args: action.args + (action.takesWindow ? [windowArg] : []), access: action.access) { call in
            var target: Window?
            if let id = call.args[windowArg.name]?.int {
                guard let window = call.manager.windows[CGWindowID(clamping: id)] else {
                    throw ControlError.failed("No managed window with id \(id)")
                }
                target = window
            }
            call.manager.dispatch(action.name, action.argument(call), inMode: call.manager.surface.inMode,
                                  target: target)
            return .null
        }
    } + FocusEffect.all.map { effect in
        let name = effect.dispatcher
        return Command(name: name, group: "focus", summary: effect.title) { call in
            call.manager.dispatch(name, "")
            return .null
        }
    }

    package static let dispatcherNames: Set<String> =
        Set(dispatchers.map(\.name) + WindowActions.all.flatMap(\.aliases))

    package static let keybindOnly: Set<String> = Set(dispatchers.filter { $0.access == .keybindOnly }.map(\.name))
}
