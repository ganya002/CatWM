import AppKit

extension Steps {
    static func resize(_ coach: Coach) -> PlannedStep? {
        guard let (grow, shrink) = coach.book.resize else { return nil }
        let shrinkCaps = KeyWords.caps(shrink, long: false)
        let growCaps = KeyWords.caps(grow, long: false)
        return PlannedStep { coach in
            var growing = true
            return Step(title: "Resize the main pane",
                 text: "",
                 target: .window, caps: shrinkCaps + growCaps,
                 tokens: shrinkCaps.count == 1 && growCaps.count == 1 ? ["shrink", "grow"] : [],
                 needsMode: true, count: 2,
                 accept: { event in
                     guard case .command(let dispatcher, let argument, _) = event,
                           let change = KeyWords.ratioDirection(dispatcher, argument) else { return nil }
                     return change == .grow ? "grow" : "shrink"
                 }, simulate: {
                     coach.windowManager.dispatch("splitratio", growing ? "+0.1" : "-0.1")
                     growing.toggle()
                 })
        }
    }

    static func zoom(_ coach: Coach) -> PlannedStep? {
        guard let zoom = coach.book.find(["fullscreen"]) else { return nil }
        return PlannedStep { coach in
            Step(title: "Fullscreen", text: "",
                 target: .window, caps: KeyWords.caps(zoom, long: false), needsMode: true, count: 2,
                 accept: { event in
                     if case .command("fullscreen", _, _) = event { return "" }
                     return nil
                 }, simulate: { coach.windowManager.dispatch("fullscreen", "") })
        }
    }

    static func float(_ coach: Coach) -> PlannedStep? {
        guard let float = coach.book.find(["togglefloating"]) else { return nil }
        return PlannedStep { coach in
            Step(title: "Float a window",
                 text: "PS: this window will not tile.",
                 target: .window, caps: KeyWords.caps(float, long: false), needsMode: true, count: 2,
                 accept: { event in
                     if case .command("togglefloating", _, _) = event { return "" }
                     return nil
                 }, simulate: { coach.windowManager.dispatch("togglefloating", "") })
        }
    }

    static func retile(_ coach: Coach) -> PlannedStep? {
        guard let retile = coach.book.find(["retile", "reevaluate"]) else { return nil }
        let key = KeyWords.keyLabel(retile.keyCode, long: false)
        return PlannedStep { coach in
            Step(title: "Snap back",
                 text: "\(key) puts every window back in the layout.",
                 target: .window, caps: KeyWords.caps(retile, long: false), needsMode: true,
                 accept: { event in
                     if case .command(let dispatcher, _, _) = event, ["retile", "reevaluate"].contains(dispatcher) {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch("retile", "") })
        }
    }

    static func layouts(_ coach: Coach) -> PlannedStep? {
        guard let next = coach.book.find(["cyclelayout"], "next") else { return nil }
        let prev = coach.book.find(["cyclelayout"], "prev")
        let keys = [next, prev].compactMap(\.self).map { KeyWords.caps($0, long: false).joined() }
        return PlannedStep { coach in
            Step(title: "Change layout",
                 text: "",
                 target: .window, caps: keys, tokens: keys.count > 1 ? ["next", "prev"] : [],
                 needsMode: true, count: 2,
                 accept: { event in
                     guard case .command("cyclelayout", let argument, _) = event else { return nil }
                     return argument.lowercased().hasPrefix("prev") ? "prev" : "next"
                 }, simulate: { coach.windowManager.dispatch("cyclelayout", "next") })
        }
    }

    static func visit(_ coach: Coach) -> PlannedStep? {
        guard let other = coach.other, let visit = coach.book.find(["workspace"], other) else { return nil }
        return PlannedStep { coach in
            Step(title: "Workspaces",
                 text: "",
                 target: .bar, caps: KeyWords.caps(visit, long: true), needsMode: true,
                 accept: { event in
                     if case .command("workspace", _, _) = event, coach.windowManager.currentWorkspace == other {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch("workspace", other) })
        }
    }

    static func back(_ coach: Coach) -> PlannedStep? {
        guard let desk = coach.desk, coach.other != nil,
              let back = coach.book.find(["workspace"], desk) else { return nil }
        let key = KeyWords.keyLabel(back.keyCode, long: false)
        return PlannedStep { coach in
            Step(title: "Nothing closed",
                 text: "Hidden workspaces keep their windows. \(key) goes back to \(desk).",
                 target: .bar, caps: KeyWords.caps(back, long: true), needsMode: true,
                 accept: { event in
                     if case .command("workspace", _, _) = event, coach.windowManager.currentWorkspace == desk {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch("workspace", desk) })
        }
    }

    static func neighbours(_ coach: Coach) -> PlannedStep? {
        guard let next = coach.book.find(["workspace"], "e+1"),
              let prev = coach.book.find(["workspace"], "e-1"),
              coach.desk != nil else { return nil }
        let keys = [prev, next].map { KeyWords.keyLabel($0.keyCode, long: false) }
        return PlannedStep { coach in
            Step(title: "Next and previous",
                 text: "\(keys[1]) is the next workspace, \(keys[0]) the previous. Go and come back.",
                 target: .bar, caps: keys, tokens: ["prev", "next"], needsMode: true, count: 2,
                 accept: { event in
                     guard case .command("workspace", let argument, _) = event else { return nil }
                     return argument.hasPrefix("e-") ? "prev" : argument.hasPrefix("e+") ? "next" : nil
                 }, simulate: {
                     let manager = coach.windowManager
                     manager.dispatch("workspace", manager.currentWorkspace == coach.desk ? "e+1" : "e-1")
                 })
        }
    }

    static func send(_ coach: Coach) -> PlannedStep? {
        guard let sendTo = coach.sendTo,
              let send = coach.book.find(["movetoworkspace", "movetoworkspacesilent"], sendTo) else { return nil }
        return PlannedStep { coach in
            Step(title: "Move to a workspace", text: "",
                 target: .window, caps: KeyWords.caps(send, long: true), needsMode: true,
                 accept: { event in
                     if case .command(let dispatcher, _, _) = event, dispatcher.hasPrefix("movetoworkspace") {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch("movetoworkspace", sendTo) })
        }
    }
}
