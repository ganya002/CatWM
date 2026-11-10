import AppKit
import CatWMKit
import MacKeysCore
import MacKeysUI
import SwiftUI

enum KeyGroup: CaseIterable, Identifiable {
    case navigation, spaces, layout, window, leave
    var id: Self { self }

    init(dispatcher: String, arg: String) {
        let (command, argument) = KeyHint.normalized(dispatcher, arg)
        switch command {
        case "movewindow": self = argument.hasPrefix("mon:") ? .spaces : .navigation
        case "movefocus", "cyclenext", "swapnext": self = .navigation
        case "workspace", "movetoworkspace", "movetoworkspacesilent", "focusmonitor", "sethomespace": self = .spaces
        case "cyclelayout", "splitratio", "layoutmsg", "layout": self = .layout
        case "submap" where argument == "reset": self = .leave
        default: self = .window
        }
    }

    var title: String {
        switch self {
        case .navigation: "Navigation"
        case .spaces: "Workspaces & displays"
        case .layout: "Layout"
        case .window: "Window"
        case .leave: "Leave mode"
        }
    }

    var color: Color {
        switch self {
        case .navigation: Theme.accent
        case .spaces: Theme.accentInk
        case .layout: Theme.inkMuted
        case .window: Theme.ink
        case .leave: Theme.inkFaint
        }
    }

    func color(onDarkKeys dark: Bool) -> Color {
        switch self {
        case .navigation: Theme.fixed(\.accent, dark: dark)
        case .spaces: Theme.fixed(\.accentInk, dark: dark)
        case .layout: Theme.fixed(\.inkMuted, dark: dark)
        case .window: Theme.fixed(\.ink, dark: dark)
        case .leave: Theme.fixed(\.inkFaint, dark: dark)
        }
    }
}
