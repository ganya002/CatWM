import AppKit

extension Steps {
    static func resize(_ coach: Coach) -> PlannedStep? {
        guard let (grow, shrink) = coach.book.resize else { return nil }
        let shrinkCaps = KeyWords.caps(shrink, long: false)
        let growCaps = KeyWords.caps(grow, long: false)
        return PlannedStep { coach in
            var growing = true
            return Step(title: "Make the column wider",
                 text: "",
                 target: .window, caps: shrinkCaps + growCaps,
                 tokens: shrinkCaps.count == 1 && growCaps.count == 1 ? ["shrink", "grow"] : [],
                 needsMode: true, count: 2,
                 accept: { event in
                     guard case .command(let dispatcher, let argument, _) = event,
                           let change = KeyWords.widthDirection(dispatcher, argument) else { return nil }
                     return change == .grow ? "grow" : "shrink"
                 }, simulate: {
                     coach.windowManager.dispatch(WindowActions.columnwidth.name, growing ? "+10" : "-10")
                     growing.toggle()
                 })
        }
    }

    static func zoom(_ coach: Coach) -> PlannedStep? {
        guard let zoom = coach.book.find([WindowActions.fullscreen]) else { return nil }
        return PlannedStep { coach in
            Step(title: "Fullscreen", text: "",
                 target: .window, caps: KeyWords.caps(zoom, long: false), needsMode: true, count: 2,
                 accept: { event in
                     if case .command(WindowActions.fullscreen.name, _, _) = event { return "" }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.fullscreen.name, "") })
        }
    }

    static func float(_ coach: Coach) -> PlannedStep? {
        guard let float = coach.book.find([WindowActions.togglefloating]) else { return nil }
        return PlannedStep { coach in
            Step(title: "Float a window",
                 text: "PS: this window will not tile.",
                 target: .window, caps: KeyWords.caps(float, long: false), needsMode: true, count: 2,
                 accept: { event in
                     if case .command(WindowActions.togglefloating.name, _, _) = event { return "" }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.togglefloating.name, "") })
        }
    }

    static func retile(_ coach: Coach) -> PlannedStep? {
        guard let retile = coach.book.find([WindowActions.retile]) else { return nil }
        let key = KeyWords.keyLabel(retile.keyCode, long: false)
        return PlannedStep { coach in
            Step(title: "Snap back",
                 text: "\(key) puts every window back in the layout.",
                 target: .window, caps: KeyWords.caps(retile, long: false), needsMode: true,
                 accept: { event in
                     if case .command(let dispatcher, _, _) = event,
                        WindowActions.named(dispatcher)?.name == WindowActions.retile.name {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.retile.name, "") })
        }
    }

    static func widths(_ coach: Coach) -> PlannedStep? {
        guard let next = coach.book.find([WindowActions.columnwidth], "cycle") else { return nil }
        return PlannedStep { coach in
            Step(title: "Change the column width",
                 text: "Each press goes to the next width.",
                 target: .window, caps: KeyWords.caps(next, long: false), needsMode: true, count: 2,
                 accept: { event in
                     guard case .command(WindowActions.columnwidth.name, let argument, _) = event,
                           argument.lowercased() == "cycle" else { return nil }
                     return ""
                 }, simulate: { coach.windowManager.dispatch(WindowActions.columnwidth.name, "cycle") })
        }
    }

    static func visit(_ coach: Coach) -> PlannedStep? {
        guard let other = coach.other, let visit = coach.book.find([WindowActions.workspace], other) else { return nil }
        return PlannedStep { coach in
            Step(title: "Workspaces",
                 text: "",
                 target: .bar, caps: KeyWords.caps(visit, long: true), needsMode: true,
                 accept: { event in
                     if case .command(WindowActions.workspace.name, _, _) = event,
                        coach.windowManager.currentWorkspace == other {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.workspace.name, other) })
        }
    }

    static func back(_ coach: Coach) -> PlannedStep? {
        guard let desk = coach.desk, coach.other != nil,
              let back = coach.book.find([WindowActions.workspace], desk) else { return nil }
        let key = KeyWords.keyLabel(back.keyCode, long: false)
        return PlannedStep { coach in
            Step(title: "Nothing closed",
                 text: "Hidden workspaces keep their windows. \(key) goes back to \(desk).",
                 target: .bar, caps: KeyWords.caps(back, long: true), needsMode: true,
                 accept: { event in
                     if case .command(WindowActions.workspace.name, _, _) = event,
                        coach.windowManager.currentWorkspace == desk {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.workspace.name, desk) })
        }
    }

    static func neighbours(_ coach: Coach) -> PlannedStep? {
        guard let next = coach.book.find([WindowActions.workspace], "e+1"),
              let prev = coach.book.find([WindowActions.workspace], "e-1"),
              coach.desk != nil else { return nil }
        let keys = [prev, next].map { KeyWords.keyLabel($0.keyCode, long: false) }
        return PlannedStep { coach in
            Step(title: "Next and previous",
                 text: "\(keys[1]) is the next workspace, \(keys[0]) the previous. Go and come back.",
                 target: .bar, caps: keys, tokens: ["prev", "next"], needsMode: true, count: 2,
                 accept: { event in
                     guard case .command(WindowActions.workspace.name, let argument, _) = event else { return nil }
                     return argument.hasPrefix("e-") ? "prev" : argument.hasPrefix("e+") ? "next" : nil
                 }, simulate: {
                     let manager = coach.windowManager
                     let step = manager.currentWorkspace == coach.desk ? "e+1" : "e-1"
                     manager.dispatch(WindowActions.workspace.name, step)
                 })
        }
    }

    static func send(_ coach: Coach) -> PlannedStep? {
        guard let sendTo = coach.sendTo,
              let send = coach.book.find([WindowActions.movetoworkspace, WindowActions.movetoworkspacesilent], sendTo)
        else { return nil }
        return PlannedStep { coach in
            Step(title: "Move to a workspace", text: "",
                 target: .window, caps: KeyWords.caps(send, long: true), needsMode: true,
                 accept: { event in
                     if case .command(let dispatcher, _, _) = event,
                        dispatcher.hasPrefix(WindowActions.movetoworkspace.name) {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.movetoworkspace.name, sendTo) })
        }
    }
}
