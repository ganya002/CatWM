import AppKit
import Carbon
import Combine
import SwiftUI

enum Actions {
    static let all: [Action] = {
        var a: [Action] = []
        func add(_ title: String, _ c: ActionCategory, _ d: String, _ args: String = "", _ symbol: String,
                 group: String? = nil, short: String? = nil, focusRequired: Bool? = nil) {
            a.append(Action(title: title, category: c, dispatcher: d, args: args, symbol: symbol,
                            group: group, short: short, focusRequired: focusRequired))
        }
        for direction in Direction.allCases {
            let dir = direction.rawValue, name = direction.title, arrow = direction.symbolName
            add("Focus \(name)", .focus, "movefocus", dir, "arrow.\(arrow)")
        }
        add("Focus Next Window", .focus, "cyclenext", "", "arrow.forward")
        add("Focus Previous Window", .focus, "cyclenext", "prev", "arrow.backward")
        add("Focus Main Window", .focus, "layoutmsg", "focusmaster", "star")
        for direction in Direction.allCases {
            let dir = direction.rawValue, name = direction.title, arrow = direction.symbolName
            add("Move Window \(name)", .move, "movewindow", dir, "arrow.\(arrow).square")
        }
        add("Swap With Next Window", .move, "swapnext", "", "arrow.left.arrow.right")
        add("Swap With Previous Window", .move, "swapnext", "prev", "arrow.right.arrow.left")
        add("Previous Layout", .layout, "cyclelayout", "prev", "rectangle.2.swap")
        add("Grow Main Pane", .layout, "splitratio", "+0.05", "arrow.left.and.right.square")
        add("Shrink Main Pane", .layout, "splitratio", "-0.05", "arrow.right.and.line.vertical.and.arrow.left")
        add("More Main Windows", .layout, "layoutmsg", "addmaster", "plus.rectangle")
        add("Fewer Main Windows", .layout, "layoutmsg", "removemaster", "minus.rectangle")
        for l in Layout.allCases {
            add("Use \(l.title) Layout", .layout, "layout", l.rawValue, "rectangle.split.2x2", group: "Use Layout", short: l.title)
        }
        add("Overview", .window, "sort", "", "square.grid.3x1.below.line.grid.1x2", focusRequired: false)
        add("Undo Last Overview Change", .window, "sort-undo", "", "arrow.uturn.backward", focusRequired: false)
        add("Focus Next Display", .displays, "focusmonitor", "+1", "display")
        add("Focus Previous Display", .displays, "focusmonitor", "-1", "display")
        add("Move Window to Previous Display", .displays, "movewindow", "mon:-1", "rectangle.portrait.and.arrow.right", focusRequired: true)
        for direction in Direction.allCases {
            let dir = direction.rawValue, name = direction.title, arrow = direction.symbolName
            add("Focus Display \(name)", .displays, "focusmonitor", dir, "arrow.\(arrow).to.line")
            add("Move Window to Display \(name)", .displays, "movewindow", "mon:\(dir)", "arrow.\(arrow).square", focusRequired: true)
        }
        add("Use This Desktop as Home", .spaces, "sethomespace", "", "house")
        for n in 1...10 { add("Workspace \(n)", .spaces, "workspace", "\(n)", "\(n).square", group: "Go to Workspace", short: "Workspace \(n)") }
        add("Previous Workspace", .spaces, "workspace", "previous", "arrow.uturn.backward.square")
        add("Next Workspace", .spaces, "workspace", "+1", "chevron.right.square")
        add("Previous Numbered Workspace", .spaces, "workspace", "-1", "chevron.left.square")
        add("Next Workspace With Windows", .spaces, "workspace", "e+1", "chevron.forward.2")
        for n in 1...10 {
            add("Move Window to Workspace \(n)", .spaces, "movetoworkspace", "\(n)", "\(n).square.fill",
                group: "Move Window to Workspace", short: "Workspace \(n)", focusRequired: true)
        }
        for n in 1...10 {
            add("Send Window to Workspace \(n)", .spaces, "movetoworkspacesilent", "\(n)", "\(n).square.fill",
                group: "Send Window to Workspace", short: "Workspace \(n)", focusRequired: true)
        }
        add("Run Command", .commands, "exec", "", "terminal")
        add("Enter Window Mode", .app, "submap", "window", "keyboard")
        add("Leave Mode", .app, "submap", "reset", "escape")
        add("Toggle Tiling", .app, "toggletiling", "", "power")
        add("Retile Windows", .app, "retile", "", "arrow.clockwise")
        add("Reload Config", .app, "reload", "", "arrow.triangle.2.circlepath")
        add("Quit Ouch", .app, "exit", "", "xmark.circle")
        for spec in PointerActions.all.sorted(by: { $0.actionOrder < $1.actionOrder }) where spec.includeInActions {
            if let before = spec.actionBefore, let index = a.firstIndex(where: { $0.id == before }) {
                a.insert(spec.action, at: index)
            } else {
                a.append(spec.action)
            }
        }
        return a
    }()

    static let byCategory: [(ActionCategory, [Action])] = ActionCategory.allCases.compactMap { c in
        let list = all.filter { $0.category == c }
        return list.isEmpty ? nil : (c, list)
    }

    enum MenuEntry: Identifiable {
        case action(Action), group(String, [Action])
        var id: String {
            switch self {
            case .action(let a): a.id
            case .group(let name, _): "group " + name
            }
        }
    }

    static func menuEntries(_ list: [Action]) -> [MenuEntry] {
        var out: [MenuEntry] = []
        for a in list {
            guard let g = a.group else { out.append(.action(a)); continue }
            if !out.contains(where: { $0.id == "group " + g }) { out.append(.group(g, list.filter { $0.group == g })) }
        }
        return out
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().split(separator: " ").joined(separator: " ")
    }

    private static func normalized(_ r: BindRow) -> (dispatcher: String, args: String) {
        var d = r.dispatcher.lowercased(), x = norm(r.args)
        if d == "setlayout" { d = "layout" }
        if d == "reevaluate" { d = "retile" }
        if d == "swapwindow" { d = "movewindow" }
        if d == "movewindowtomonitor" { d = "movewindow"; x = "mon:" + x }
        if d == "layoutmsg" {
            switch x {
            case "cyclenext": d = "cyclenext"; x = ""
            case "cycleprev": d = "cyclenext"; x = "prev"
            case "swapnext": d = "swapnext"; x = ""
            case "swapprev": d = "swapnext"; x = "prev"
            case "orientationnext": d = "cyclelayout"; x = "next"
            case "orientationprev": d = "cyclelayout"; x = "prev"
            default: break
            }
        }
        if d == "cyclelayout" && x.isEmpty { x = "next" }
        if d == "splitratio", let v = Double(x.replacingOccurrences(of: "+", with: "")) { x = v > 0 ? "+0.05" : "-0.05" }
        if d == "layoutmsg", x.hasPrefix("mfact"), let v = Double(x.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
            d = "splitratio"; x = v > 0 ? "+0.05" : "-0.05"
        }

        return (d, x)
    }

    static func match(_ r: BindRow) -> Action? {
        let (d, x) = normalized(r)
        if d == "exec" { return all.first { $0.dispatcher == "exec" } }
        return all.first { $0.dispatcher == d && norm($0.args) == x }
    }

    static func requiresFocus(_ r: BindRow) -> Bool {
        let (d, _) = normalized(r)
        return (match(r) ?? all.first { $0.dispatcher == d })?.requiresFocus ?? false
    }

    static func same(_ d1: String, _ a1: String, _ d2: String, _ a2: String) -> Bool {
        let m1 = match(BindRow(mods: "", key: "", dispatcher: d1, args: a1))
        let m2 = match(BindRow(mods: "", key: "", dispatcher: d2, args: a2))
        if let m1, let m2 { return m1.dispatcher == m2.dispatcher && m1.args == m2.args }
        return d1.lowercased() == d2.lowercased() && a1.lowercased() == a2.lowercased()
    }

    static func isNextWorkspace(_ dispatcher: String, _ args: String) -> Bool {
        ["movetoworkspace", "movetoworkspacesilent"].contains(dispatcher.lowercased())
            && ["e+1", "+1", "r+1", "m+1"].contains(args.lowercased())
    }

    static func rangeSummary(_ r: BindRow) -> (title: String, category: ActionCategory, symbol: String)? {
        guard case .success(let pairs) = BindRange.pairs(key: r.key, dispatcher: r.dispatcher, arg: r.args), pairs.count > 1
        else { return nil }
        let actions = pairs.map { match(BindRow(mods: "", key: "", dispatcher: r.dispatcher, args: $0.arg)) }
        guard let first = actions.first ?? nil else { return nil }
        if Set(pairs.map(\.arg)).count == 1 { return (first.title, first.category, first.symbol) }
        let titles = actions.map { $0?.title ?? "" }
        let lastWords = titles.map { $0.split(separator: " ").last.map(String.init) ?? "" }
        let prefixes = Set(zip(titles, lastWords).map { $0.dropLast($1.count) })
        if titles.allSatisfy({ !$0.isEmpty }), prefixes.count == 1, let prefix = prefixes.first {
            let numeric = lastWords.allSatisfy { Int($0) != nil }
            let tail = numeric ? "\(lastWords.first!)…\(lastWords.last!)" : lastWords.joined(separator: ", ")
            return (prefix + tail, first.category, first.symbol)
        }
        return ("\(r.dispatcher) \(r.args)", first.category, first.symbol)
    }

    static let dispatchers: [String] = {
        var names = DispatcherNames.all
        for feature in FocusDim.features {
            let index = names.firstIndex(of: feature.dispatcherBefore) ?? names.endIndex
            names.insert(feature.pointer.dispatcher, at: index)
        }
        return names
    }()
}
