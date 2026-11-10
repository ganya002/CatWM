import AppKit
import CatWMKit

extension Steps {
    static func modeOn(_ coach: Coach, title: String? = nil, text: String? = nil) -> PlannedStep? {
        let book = coach.book
        guard book.enter != nil, !book.mode.isEmpty else { return nil }
        let name = book.mode.lowercased()
        return PlannedStep { coach in
            Step(title: title ?? "\(name.capitalized) mode",
                 text: text ?? "Access all shortcuts within \(name) mode. Central concept of this tiling manager.",
                 caps: coach.book.enterCaps(long: true), accept: { event in
                     if case .mode(let submap) = event, !submap.isEmpty { return "" }
                     return nil
                 }, simulate: { Hotkeys.shared.setSubmap(coach.book.mode) })
        }
    }

    static func modeOff(_ coach: Coach, recall: Bool = false) -> PlannedStep? {
        let book = coach.book
        guard !book.mode.isEmpty else { return nil }
        let keys = book.exits.map { KeyWords.keyLabel($0.keyCode, long: false) }
        let name = book.mode.lowercased()
        return PlannedStep { _ in
            Step(title: "Leave \(name) mode",
                 text: recall ? "From memory." : (keys.isEmpty ? "Click anywhere. The edge glow fades."
                    : "Press \(KeyWords.list(keys, orJoin: true)) or click anywhere. The edge glow fades."),
                 target: .mode, caps: keys, recall: recall, accept: { event in
                     if case .mode(let submap) = event, submap.isEmpty { return "" }
                     if case .tick = event, Hotkeys.shared.submap.isEmpty { return "" }
                     return nil
                 }, simulate: { Hotkeys.shared.setSubmap("") })
        }
    }

    static func help(_ coach: Coach) -> PlannedStep? {
        guard coach.windowManager.config.keyboardHelp, !coach.book.mode.isEmpty else { return nil }
        let key = coach.windowManager.config.keyboardHelpKey
        return PlannedStep { _ in
            var opened = false
            return Step(title: "Key Map",
                        text: "If you ever forget a shortcut, you'll find an overview easily here.",
                        caps: [key, key], tokens: ["open", "close"], needsMode: true, accept: { event in
                            guard case .tick = event else { return nil }
                            if KeyHelp.shared.isVisible { opened = true; return "open" }
                            return opened ? "close" : nil
                        }, simulate: { KeyHelp.shared.toggle() })
        }
    }

    static func focus(_ coach: Coach) -> PlannedStep? {
        let book = coach.book
        let dirs = book.directions.compactMap { direction in
            book.find([WindowActions.movefocus], direction).map { (direction, $0) }
        }
        guard dirs.count == 4 else { return nil }
        let keys = dirs.map { KeyWords.keyLabel($0.1.keyCode, long: false) }
        return PlannedStep { coach in
            var left = coach.book.directions
            return Step(title: "Move focus",
                        text: "",
                        target: .window, caps: keys, tokens: book.directions, needsMode: true, count: 4,
                        accept: { event in
                            guard case .command(WindowActions.movefocus.name, let argument, _) = event else {
                                return nil
                            }
                            return KeyWords.dirToken(argument)
                        }, simulate: {
                            let direction = left.isEmpty ? "r" : left.removeFirst()
                            coach.windowManager.dispatch(WindowActions.movefocus.name, direction)
                        })
        }
    }

    static func cycle(_ coach: Coach) -> PlannedStep? {
        guard let next = coach.book.find([WindowActions.cyclenext], "") else { return nil }
        let key = KeyWords.keyLabel(next.keyCode, long: false)
        return PlannedStep { coach in
            Step(title: "Next window",
                 text: "\(key) cycles focus through every window. Press it a few times.",
                 target: .window, caps: KeyWords.caps(next, long: false), needsMode: true, count: 3,
                 accept: { event in
                     if case .command(WindowActions.cyclenext.name, _, _) = event { return "" }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.cyclenext.name, "") })
        }
    }

    static func move(_ coach: Coach) -> PlannedStep? {
        let book = coach.book
        let dirs = book.directions.compactMap { book.find([WindowActions.movewindow, WindowActions.swapwindow], $0) }
        guard dirs.count == 4 else { return nil }
        let mods = KeyWords.modLabels(dirs[0].mods, long: true)
        let keys = dirs.map { KeyWords.keyLabel($0.keyCode, long: false) }
        return PlannedStep { coach in
            Step(title: "Move a window",
                 text: "",
                 target: .window, caps: mods + keys, needsMode: true, count: 2,
                 accept: { event in
                     guard case .command(let dispatcher, let argument, _) = event else { return nil }
                     let lowered = argument.lowercased()
                     if dispatcher == WindowActions.movewindow.name, !lowered.hasPrefix("mon:") {
                         return KeyWords.dirToken(argument) ?? ""
                     }
                     if [WindowActions.swapwindow.name, WindowActions.swapnext.name].contains(dispatcher)
                        || (dispatcher == WindowActions.layoutmsg.name && lowered.hasPrefix("swap")) {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.swapnext.name, "") })
        }
    }

    static func main(_ coach: Coach) -> PlannedStep? {
        guard let swap = coach.book.find([WindowActions.layoutmsg], "swapwithmaster") else { return nil }
        return PlannedStep { coach in
            Step(title: "Promote a window",
                 text: "",
                 target: .window, caps: KeyWords.caps(swap, long: false), needsMode: true,
                 accept: { event in
                     if case .command(WindowActions.layoutmsg.name, let argument, _) = event,
                        argument.lowercased() == "swapwithmaster" {
                         return ""
                     }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.layoutmsg.name, "swapwithmaster") })
        }
    }

    static func mainCount(_ coach: Coach) -> PlannedStep? {
        guard let add = coach.book.find([WindowActions.layoutmsg], "addmaster"),
              let remove = coach.book.find([WindowActions.layoutmsg], "removemaster") else { return nil }
        let text = "\(KeyWords.keyWord(add)) adds a window to the main pane, "
            + "\(KeyWords.keyWord(remove)) takes one out. Try both."
        let caps = KeyWords.caps(add, long: false) + [KeyWords.keyLabel(remove.keyCode, long: false)]
        return PlannedStep { coach in
            var adding = true
            var seen: Set<String> = []
            return Step(title: "More main windows",
                        text: text,
                        target: .window, caps: caps,
                        tokens: [], needsMode: true, count: 2,
                        accept: { event in
                            guard case .command(WindowActions.layoutmsg.name, let argument, _) = event else {
                                return nil
                            }
                            guard ["addmaster", "removemaster"].contains(argument.lowercased()) else { return nil }
                            return seen.insert(argument.lowercased()).inserted ? "" : nil
                        }, simulate: {
                            let message = adding ? "addmaster" : "removemaster"
                            coach.windowManager.dispatch(WindowActions.layoutmsg.name, message)
                            adding.toggle()
                        })
        }
    }
}
