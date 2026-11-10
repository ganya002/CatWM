import AppKit

extension CommandRegistry {
    package static let dispatchers: [Command] = WindowActions.all.map { action in
        Command(name: action.name, group: action.group, summary: action.summary, args: action.args,
                access: action.access) { call in
            call.manager.dispatch(action.name, action.argument(call))
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
