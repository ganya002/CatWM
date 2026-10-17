import AppKit
import SwiftUI
import MacKeysCore

enum ActionMenuItems {
    static func items(current: Action? = nil, pick: @escaping (Action) -> Void) -> [MenuItem] {
        func row(_ a: Action, _ title: String) -> MenuItem {
            MenuItem(id: "a.\(a.id)", kind: current == nil ? .action : .radio, label: title, checked: a.id == current?.id,
                     action: { pick(a) })
        }
        func sub(_ id: String, _ label: String, symbol: String?, _ children: [MenuItem]) -> MenuItem {
            MenuItem(id: id, kind: .sub, label: label, symbol: symbol, width: MenuItem.fitWidth(children), children: children)
        }
        return Actions.byCategory.map { cat, actions in
            sub("c.\(cat.rawValue)", cat.rawValue, symbol: cat.symbol, Actions.menuEntries(actions).map { entry in
                switch entry {
                case .action(let a): row(a, a.title)
                case .group(let name, let list): sub("g.\(name)", name, symbol: nil, list.map { row($0, $0.short ?? $0.title) })
                }
            })
        }
    }
}
