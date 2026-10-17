import AppKit
import SwiftUI

struct MenuItem: Identifiable {
    enum Kind { case action, check, radio, sub, label, separator, essentials, workspaces, layoutPicker, attention, footer }

    var id: String
    var kind: Kind = .action
    var label = ""
    var symbol: String? = nil
    var image: NSImage? = nil
    var shortcut: [String] = []
    var value: String? = nil
    var checked = false
    var danger = false
    var enabled = true
    var hidden = false
    var keywords = ""
    var width: CGFloat = Theme.submenuWidth
    var children: [MenuItem] = []
    var keepOpen = false
    var rotates = false
    var badge: Int? = nil
    var dot = false
    var action: (() -> Void)? = nil

    var selectable: Bool {
        guard enabled, !hidden else { return false }
        return [.action, .check, .radio, .sub, .footer].contains(kind)
    }

    static func sep(_ id: String) -> MenuItem { MenuItem(id: id, kind: .separator) }
    static func label(_ id: String, _ text: String, shortcut: [String] = []) -> MenuItem {
        MenuItem(id: id, kind: .label, label: text, shortcut: shortcut)
    }
}
