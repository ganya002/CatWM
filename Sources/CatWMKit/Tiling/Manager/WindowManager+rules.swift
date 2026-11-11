import AppKit

extension WindowManager {
    package func run(_ binding: KeyBinding) {
        guard let function = binding.function else { return dispatch(binding.dispatcher, binding.arg) }
        guard let window = focusedWindow() else { return }
        let snapshot = ConfigEngine.WindowSnapshot(
            title: window.title ?? "", app: window.bundleID ?? "", pid: Int(window.pid),
            frame: animator.destination(window.id) ?? window.cachedFrame)
        store.call(function: function, window: snapshot) { [weak self] result in
            guard let self else { return }
            if let failure = result.failure {
                Log.info("config: \(failure.text)")
                surface.showHUD("Config: 1 error(s), see Console", on: currentScreen()?.nsScreen)
            }
            for action in result.actions { dispatch(action.dispatcher, action.arg) }
        }
    }

    func markForRules(_ window: Window) {
        guard !config.windowRules.isEmpty, !windowsToMatch.contains(window.id) else { return }
        windowsToMatch.append(window.id)
    }

    func applyDueWindowRules() {
        guard !windowsToMatch.isEmpty else { return }
        let due = windowsToMatch
        windowsToMatch = []
        let rules = config.windowRules
        for id in due {
            guard let window = windows[id] else { continue }
            let matching = matchingRules(of: window, in: rules)
            let started = matching.subtracting(window.matchedRules).sorted()
            window.matchedRules = matching
            guard !restoringTemplate else { continue }
            for index in started {
                for action in rules[index].actions { run(action, on: window) }
            }
        }
    }

    func applyFloatingChanges(from old: Config) {
        let (oldRules, newRules) = (old.windowRules, config.windowRules)
        for window in windows.values {
            let list = shouldFloat(window)
            var changed = window.autoFloating != list
            var rule = Window.FloatingChoice.automatic
            if !oldRules.isEmpty || !newRules.isEmpty {
                let facts = ruleFacts(of: window)
                let before = floatingRule(of: oldRules, facts)
                rule = floatingRule(of: newRules, facts)
                changed = outcome(before, auto: window.autoFloating) != outcome(rule, auto: list)
                window.matchedRules = matchingRules(of: window, in: newRules, facts)
            }
            window.autoFloating = list
            if changed, !tabs.isGrouped(window.id) { window.userFloating = rule }
        }
    }

    private func run(_ action: RuleAction, on window: Window) {
        if let refusal = scopeRefusal(action.dispatcher) {
            Log.info(refusal)
            return
        }
        guard let command = WindowActions.named(action.dispatcher) else {
            Log.info("unknown dispatcher \(action.dispatcher)")
            return
        }
        command.run(ActionContext(manager: self, arg: action.arg.trimmingCharacters(in: .whitespaces), target: window))
        switch action.dispatcher {
        case WindowActions.setfloating.name: window.userFloating = .chosen(true)
        case WindowActions.settiled.name: window.userFloating = .chosen(false)
        default: break
        }
    }

    private func matchingRules(of window: Window, in rules: [WindowRule], _ facts: Facts? = nil) -> Set<Int> {
        guard !rules.isEmpty else { return [] }
        let facts = facts ?? ruleFacts(of: window)
        return Set(rules.indices.filter { rules[$0].when.holds(facts) })
    }

    private func floatingRule(of rules: [WindowRule], _ facts: Facts) -> Window.FloatingChoice {
        var choice = Window.FloatingChoice.automatic
        for rule in rules where rule.when.holds(facts) {
            for action in rule.actions {
                switch action.dispatcher {
                case WindowActions.setfloating.name: choice = .chosen(true)
                case WindowActions.settiled.name: choice = .chosen(false)
                default: break
                }
            }
        }
        return choice
    }

    private func outcome(_ rule: Window.FloatingChoice, auto: Bool) -> Bool {
        if case .chosen(let floating) = rule { return floating }
        return auto
    }

    private func ruleFacts(of window: Window) -> Facts {
        var facts: Facts = [
            .pid: .int(Int(window.pid)), .role: .string(kAXStandardWindowSubrole), .floating: .bool(window.isFloating),
            .minimized: .bool(window.minimized), .fullscreen: .bool(window.fullscreen)
        ]
        if let bundle = window.bundleID { facts[.app] = .string(bundle) }
        if let title = window.title { facts[.title] = .string(title) }
        if let workspace = workspaceOf[window.id] {
            facts[.workspace] = .array([.string(workspace)] + (labels[workspace].map { [.string($0)] } ?? []))
        }
        if let screen = screen(of: window) {
            facts[.display] = .array([.string(screen.uuid), .string(screen.name),
                                      .string(screen.isBuiltin ? "builtin" : "external")])
        }
        return facts
    }
}
