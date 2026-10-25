import AppKit

extension CommandRegistry {
    static let dispatchers: [Command] = WindowActions.all.map { action in
        Command(name: action.name, group: action.group, summary: action.summary, args: action.args,
                access: action.access) { call in
            try refuseOutsideScope(action.name)
            WindowManager.shared.dispatch(action.name, action.argument(call))
            return .null
        }
    } + FocusDim.features.map { feature in
        let name = feature.pointer.dispatcher
        return Command(name: name, group: "focus", summary: feature.pointer.action.title) { _ in
            try refuseOutsideScope(name)
            WindowManager.shared.dispatch(name, "")
            return .null
        }
    }

    static func refuseOutsideScope(_ dispatcher: String) throws {
        if let refusal = WindowManager.shared.scopeRefusal(dispatcher) { throw ControlError.failed(refusal) }
    }

    static let keybindOnly: Set<String> = Set(dispatchers.filter { $0.access == .keybindOnly }.map(\.name))
}
