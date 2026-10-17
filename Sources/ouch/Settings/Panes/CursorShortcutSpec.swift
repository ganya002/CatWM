import AppKit

struct CursorShortcutSpec: Identifiable {
    let id: String
    let action: Action
    let title: String
    var menuIdentity: String? = nil
    var menuLabel: String? = nil
    var menuDispatcher: String? = nil
    var menuArgs: String? = nil
    var actionBefore: String? = nil
    var actionOrder = 0
    var includeInActions = true
    var menuID: String { menuIdentity ?? id }
    var menuTitle: String { menuLabel ?? title }
    var dispatcher: String { menuDispatcher ?? action.dispatcher }
    var args: String { menuArgs ?? action.args }
    var nextWorkspace = false
    var hint: String? = nil
    var available: (Context) -> Bool = { _ in true }
    var selected: (Context) -> Bool = { _ in false }
    var destructive = false

    struct Context {
        let floating: Bool
        let tiled: Bool
        let zoomed: Bool
        let nativeFullscreen: Bool
        let canMakeMain: Bool
        let multipleLayouts: Bool
        let multipleDisplays: Bool
        let virtualWorkspace: Bool
    }
}

enum PointerActions {
    static let all: [CursorShortcutSpec] = [
        CursorShortcutSpec(id: "float", action: Action(title: "Toggle Floating", category: .window, dispatcher: "togglefloating", args: "", symbol: "macwindow.on.rectangle"),
                           title: "Float or tile", menuLabel: "Float", actionBefore: "sort ", hint: "Float", selected: { $0.floating }),
        CursorShortcutSpec(id: "zoom", action: Action(title: "Toggle Fullscreen", category: .window, dispatcher: "fullscreen", args: "", symbol: "arrow.up.left.and.arrow.down.right"),
                           title: "Zoom", actionBefore: "sort ", hint: "Full", available: { $0.tiled }, selected: { $0.zoomed }),
        CursorShortcutSpec(id: "native", action: Action(title: "Toggle macOS Full Screen", category: .window, dispatcher: "nativefullscreen", args: "", symbol: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"),
                           title: "Native Full Screen", menuIdentity: "nativefullscreen", actionBefore: "sort ", hint: "Max", selected: { $0.nativeFullscreen }),
        CursorShortcutSpec(id: "main", action: Action(title: "Swap With Main Window", category: .move, dispatcher: "layoutmsg", args: "swapwithmaster", symbol: "star.square"),
                           title: "Make Main", actionBefore: "swapnext ", available: { $0.canMakeMain }),
        CursorShortcutSpec(id: "layout", action: Action(title: "Next Layout", category: .layout, dispatcher: "cyclelayout", args: "next", symbol: "rectangle.2.swap"),
                           title: "Next Layout", actionBefore: "cyclelayout prev", available: { $0.multipleLayouts }),
        CursorShortcutSpec(id: "display", action: Action(title: "Move Window to Next Display", category: .displays, dispatcher: "movewindow", args: "mon:+1", symbol: "rectangle.portrait.and.arrow.right", focusRequired: true),
                           title: "Send to Next Display", menuDispatcher: "movewindowtomonitor", menuArgs: "+1", actionBefore: "movewindow mon:-1", available: { $0.multipleDisplays }),
        CursorShortcutSpec(id: "workspace", action: Action(title: "Send Window to Next Workspace", category: .spaces, dispatcher: "movetoworkspacesilent", args: "+1", symbol: "arrow.right.square", focusRequired: true),
                           title: "Send to Next Workspace", includeInActions: false, nextWorkspace: true, available: { $0.virtualWorkspace }),
    ] + FocusDim.features.map(\.pointer) + [
        CursorShortcutSpec(id: "minimize", action: Action(title: "Minimize Window", category: .window, dispatcher: "minimize", args: "", symbol: "minus.square"),
                           title: "Minimize", actionBefore: "sort ", actionOrder: 1, hint: "Min"),
        CursorShortcutSpec(id: "close", action: Action(title: "Close Window", category: .window, dispatcher: "killactive", args: "", symbol: "xmark.square"),
                           title: "Close", actionBefore: "sort ", hint: "Close", destructive: true),
    ]

    static func hint(_ dispatcher: String) -> String? {
        all.first { $0.hint != nil && $0.dispatcher == dispatcher }?.hint
    }
}
