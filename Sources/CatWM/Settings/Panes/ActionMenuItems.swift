import AppKit
import MacKeysCore
import SwiftUI

enum ActionMenuItems {
    static func items(current: Action? = nil, pick: @escaping (Action) -> Void) -> [MenuItem] {
        func row(_ action: Action, _ title: String) -> MenuItem {
            MenuItem(id: "a.\(action.id)", kind: current == nil ? .action : .radio, label: title,
                     checked: action.id == current?.id,
                     action: { pick(action) })
        }
        func sub(_ id: String, _ label: String, _ children: [MenuItem]) -> MenuItem {
            MenuItem(id: id, kind: .sub, label: label, width: MenuItem.fitWidth(children),
                     children: children)
        }
        return Actions.byCategory.map { cat, actions in
            sub("c.\(cat.rawValue)", cat.rawValue, Actions.menuEntries(actions).map { entry in
                switch entry {
                case .action(let action): row(action, action.title)
                case .group(let name, let list):
                    sub("g.\(name)", name, list.map { row($0, $0.short ?? $0.title) })
                }
            })
        }
    }
}
