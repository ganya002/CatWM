import Foundation

package enum Actions {
    package static let all: [Action] = {
        let rows = WindowActions.all.flatMap { action in
            action.pickers.map { (picker: $0, action: action.action(for: $0)) }
        }
            .enumerated().map { index, row in
                (key: (ActionCategory.allCases.firstIndex(of: row.picker.category) ?? 0, row.picker.order, index),
                 action: row.action)
            }
        var actions = rows.sorted { $0.key < $1.key }.map(\.action)
        for spec in PointerActions.all.sorted(by: { $0.actionOrder < $1.actionOrder }) where spec.includeInActions {
            if let before = spec.actionBefore, let index = actions.firstIndex(where: { $0.id == before }) {
                actions.insert(spec.action, at: index)
            } else {
                actions.append(spec.action)
            }
        }
        return actions
    }()

    package static let byCategory: [(ActionCategory, [Action])] = ActionCategory.allCases.compactMap { category in
        let list = all.filter { $0.category == category }
        return list.isEmpty ? nil : (category, list)
    }

    package enum MenuEntry: Identifiable {
        case action(Action), group(String, [Action])
        package var id: String {
            switch self {
            case .action(let action): action.id
            case .group(let name, _): "group " + name
            }
        }
    }

    package static func menuEntries(_ list: [Action]) -> [MenuEntry] {
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
        if let action = WindowActions.named(dispatcher) { dispatcher = action.name }
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

    package static func match(_ row: BindRow) -> Action? {
        let (dispatcher, args) = normalized(row)
        if dispatcher == "exec" { return all.first { $0.dispatcher == "exec" } }
        return all.first { $0.dispatcher == dispatcher && norm($0.args) == args }
    }

    package static func requiresFocus(_ row: BindRow) -> Bool {
        let (dispatcher, _) = normalized(row)
        return (match(row) ?? all.first { $0.dispatcher == dispatcher })?.requiresFocus ?? false
    }

    package static func same(_ firstDispatcher: String, _ firstArgs: String,
                             _ secondDispatcher: String, _ secondArgs: String) -> Bool {
        let firstMatch = match(BindRow(mods: "", key: "", dispatcher: firstDispatcher, args: firstArgs))
        let secondMatch = match(BindRow(mods: "", key: "", dispatcher: secondDispatcher, args: secondArgs))
        if let firstMatch, let secondMatch {
            return firstMatch.dispatcher == secondMatch.dispatcher && firstMatch.args == secondMatch.args
        }
        return firstDispatcher.lowercased() == secondDispatcher.lowercased()
            && firstArgs.lowercased() == secondArgs.lowercased()
    }

    package static func isNextWorkspace(_ dispatcher: String, _ args: String) -> Bool {
        ["movetoworkspace", "movetoworkspacesilent"].contains(dispatcher.lowercased())
            && ["e+1", "+1", "r+1", "m+1"].contains(args.lowercased())
    }

    package struct RangeSummary {
        package let title: String
        package let category: ActionCategory
        package let symbol: String
    }

    package static func rangeSummary(_ row: BindRow) -> RangeSummary? {
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

    package static let dispatchers: [String] = {
        var names = WindowActions.all.flatMap { [$0.name] + $0.aliases }
        for effect in FocusEffect.all {
            let index = names.firstIndex(of: effect.dispatcherBefore) ?? names.endIndex
            names.insert(effect.dispatcher, at: index)
        }
        return names
    }()
}
