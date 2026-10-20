import AppKit
import Carbon
import Combine
import SwiftUI

enum Actions {
    static let all: [Action] = {
        var actions: [Action] = []
        func add(_ title: String, _ category: ActionCategory, _ dispatcher: String, _ args: String = "",
                 _ symbol: String, group: String? = nil, short: String? = nil,
                 focusRequired: FocusRequirement = .byCategory) {
            actions.append(Action(title: title, category: category, dispatcher: dispatcher, args: args, symbol: symbol,
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
        add("Swap Sides", .layout, "layoutmsg", "swapsides", "arrow.left.arrow.right.square")
        add("More Main Windows", .layout, "layoutmsg", "addmaster", "plus.rectangle")
        add("Fewer Main Windows", .layout, "layoutmsg", "removemaster", "minus.rectangle")
        for layout in Layout.allCases {
            add("Use \(layout.title) Layout", .layout, "layout", layout.rawValue, "rectangle.split.2x2",
                group: "Use Layout", short: layout.title)
        }
        add("Overview", .window, "sort", "", "square.grid.3x1.below.line.grid.1x2", focusRequired: false)
        add("Switch Windows", .window, "switcher", "", "rectangle.stack", focusRequired: false)
        add("Switch Windows Backward", .window, "switcher", "prev", "rectangle.stack", focusRequired: false)
        add("Undo Last Overview Change", .window, "sort-undo", "", "arrow.uturn.backward", focusRequired: false)
        add("Focus Next Display", .displays, "focusmonitor", "+1", "display")
        add("Focus Previous Display", .displays, "focusmonitor", "-1", "display")
        add("Move Window to Previous Display", .displays, "movewindow", "mon:-1", "rectangle.portrait.and.arrow.right",
            focusRequired: true)
        for direction in Direction.allCases {
            let dir = direction.rawValue, name = direction.title, arrow = direction.symbolName
            add("Focus Display \(name)", .displays, "focusmonitor", dir, "arrow.\(arrow).to.line")
            add("Move Window to Display \(name)", .displays, "movewindow", "mon:\(dir)", "arrow.\(arrow).square",
                focusRequired: true)
        }
        add("Use This Desktop as Home", .spaces, "sethomespace", "", "house")
        for number in 1...10 {
            add("Workspace \(number)", .spaces, "workspace", "\(number)", "\(number).square",
                group: "Go to Workspace", short: "Workspace \(number)")
        }
        add("Previous Workspace", .spaces, "workspace", "previous", "arrow.uturn.backward.square")
        add("Next Workspace", .spaces, "workspace", "+1", "chevron.right.square")
        add("Previous Numbered Workspace", .spaces, "workspace", "-1", "chevron.left.square")
        add("Next Workspace With Windows", .spaces, "workspace", "e+1", "chevron.forward.2")
        for number in 1...10 {
            add("Move Window to Workspace \(number)", .spaces, "movetoworkspace", "\(number)", "\(number).square.fill",
                group: "Move Window to Workspace", short: "Workspace \(number)", focusRequired: true)
        }
        for number in 1...10 {
            add("Send Window to Workspace \(number)", .spaces, "movetoworkspacesilent", "\(number)",
                "\(number).square.fill", group: "Send Window to Workspace", short: "Workspace \(number)",
                focusRequired: true)
        }
        add("Run Command", .commands, "exec", "", "terminal")
        add("Enter Window Mode", .app, "submap", "window", "keyboard")
        add("Leave Mode", .app, "submap", "reset", "escape")
        add("Toggle Tiling", .app, "toggletiling", "", "power")
        add("Retile Windows", .app, "retile", "", "arrow.clockwise")
        add("Reload Config", .app, "reload", "", "arrow.triangle.2.circlepath")
        add("Quit Ouch", .app, "exit", "", "xmark.circle")
        for spec in PointerActions.all.sorted(by: { $0.actionOrder < $1.actionOrder }) where spec.includeInActions {
            if let before = spec.actionBefore, let index = actions.firstIndex(where: { $0.id == before }) {
                actions.insert(spec.action, at: index)
            } else {
                actions.append(spec.action)
            }
        }
        return actions
    }()

    static let byCategory: [(ActionCategory, [Action])] = ActionCategory.allCases.compactMap { category in
        let list = all.filter { $0.category == category }
        return list.isEmpty ? nil : (category, list)
    }

    enum MenuEntry: Identifiable {
        case action(Action), group(String, [Action])
        var id: String {
            switch self {
            case .action(let action): action.id
            case .group(let name, _): "group " + name
            }
        }
    }

    static func menuEntries(_ list: [Action]) -> [MenuEntry] {
        var out: [MenuEntry] = []
        for action in list {
            guard let group = action.group else { out.append(.action(action)); continue }
            if !out.contains(where: { $0.id == "group " + group }) {
                out.append(.group(group, list.filter { $0.group == group }))
            }
        }
        return out
    }

    private static func norm(_ text: String) -> String {
        text.lowercased().split(separator: " ").joined(separator: " ")
    }

    private static func normalized(_ row: BindRow) -> (dispatcher: String, args: String) {
        var dispatcher = row.dispatcher.lowercased(), args = norm(row.args)
        if dispatcher == "setlayout" { dispatcher = "layout" }
        if dispatcher == "reevaluate" { dispatcher = "retile" }
        if dispatcher == "swapwindow" { dispatcher = "movewindow" }
        if dispatcher == "movewindowtomonitor" { dispatcher = "movewindow"; args = "mon:" + args }
        if dispatcher == "layoutmsg" {
            switch args {
            case "cyclenext": dispatcher = "cyclenext"; args = ""
            case "cycleprev": dispatcher = "cyclenext"; args = "prev"
            case "swapnext": dispatcher = "swapnext"; args = ""
            case "swapprev": dispatcher = "swapnext"; args = "prev"
            case "orientationnext": dispatcher = "cyclelayout"; args = "next"
            case "orientationprev": dispatcher = "cyclelayout"; args = "prev"
            default: break
            }
        }
        if dispatcher == "cyclelayout" && args.isEmpty { args = "next" }
        if dispatcher == "splitratio", let ratio = Double(args.replacingOccurrences(of: "+", with: "")) {
            args = ratio > 0 ? "+0.05" : "-0.05"
        }
        if dispatcher == "layoutmsg", args.hasPrefix("mfact"),
           let ratio = Double(args.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
            dispatcher = "splitratio"; args = ratio > 0 ? "+0.05" : "-0.05"
        }

        return (dispatcher, args)
    }

    static func match(_ row: BindRow) -> Action? {
        let (dispatcher, args) = normalized(row)
        if dispatcher == "exec" { return all.first { $0.dispatcher == "exec" } }
        return all.first { $0.dispatcher == dispatcher && norm($0.args) == args }
    }

    static func requiresFocus(_ row: BindRow) -> Bool {
        let (dispatcher, _) = normalized(row)
        return (match(row) ?? all.first { $0.dispatcher == dispatcher })?.requiresFocus ?? false
    }

    static func same(_ firstDispatcher: String, _ firstArgs: String,
                     _ secondDispatcher: String, _ secondArgs: String) -> Bool {
        let firstMatch = match(BindRow(mods: "", key: "", dispatcher: firstDispatcher, args: firstArgs))
        let secondMatch = match(BindRow(mods: "", key: "", dispatcher: secondDispatcher, args: secondArgs))
        if let firstMatch, let secondMatch {
            return firstMatch.dispatcher == secondMatch.dispatcher && firstMatch.args == secondMatch.args
        }
        return firstDispatcher.lowercased() == secondDispatcher.lowercased()
            && firstArgs.lowercased() == secondArgs.lowercased()
    }

    static func isNextWorkspace(_ dispatcher: String, _ args: String) -> Bool {
        ["movetoworkspace", "movetoworkspacesilent"].contains(dispatcher.lowercased())
            && ["e+1", "+1", "r+1", "m+1"].contains(args.lowercased())
    }

    struct RangeSummary {
        let title: String
        let category: ActionCategory
        let symbol: String
    }

    static func rangeSummary(_ row: BindRow) -> RangeSummary? {
        guard case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args),
              pairs.count > 1
        else { return nil }
        let actions = pairs.map { match(BindRow(mods: "", key: "", dispatcher: row.dispatcher, args: $0.arg)) }
        guard case let first?? = actions.first else { return nil }
        if Set(pairs.map(\.arg)).count == 1 {
            return RangeSummary(title: first.title, category: first.category, symbol: first.symbol)
        }
        let titles = actions.map { $0?.title ?? "" }
        let lastWords = titles.map { $0.split(separator: " ").last.map(String.init) ?? "" }
        let prefixes = Set(zip(titles, lastWords).map { $0.dropLast($1.count) })
        if titles.allSatisfy({ !$0.isEmpty }), prefixes.count == 1, let prefix = prefixes.first {
            let numeric = lastWords.allSatisfy { Int($0) != nil }
            let tail = numeric
                ? "\(lastWords.first ?? "")…\(lastWords.last ?? "")"
                : lastWords.joined(separator: ", ")
            return RangeSummary(title: prefix + tail, category: first.category, symbol: first.symbol)
        }
        return RangeSummary(title: "\(row.dispatcher) \(row.args)", category: first.category, symbol: first.symbol)
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
