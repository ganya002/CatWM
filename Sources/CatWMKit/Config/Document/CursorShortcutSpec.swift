import AppKit

package struct CursorShortcutSpec: Identifiable {
    package let id: String
    package let action: Action
    package let title: String
    package var menuLabel: String?
    package var menuDispatcher: String?
    package var menuArgs: String?
    package var actionBefore: String?
    package var actionOrder = 0
    package var includeInActions = true
    package var menuTitle: String { menuLabel ?? title }
    package var dispatcher: String { menuDispatcher ?? action.dispatcher }
    package var args: String { menuArgs ?? action.args }
    package var nextWorkspace = false
    package var hint: String?
    package var available: (Context) -> Bool = { _ in true }
    package var selected: (Context) -> Bool = { _ in false }
    package var destructive = false

    package struct Context {
        package let floating: Bool
        package let tiled: Bool
        package let zoomed: Bool
        package let nativeFullscreen: Bool
        package let canMakeMain: Bool
        package let multipleLayouts: Bool
        package let multipleDisplays: Bool
        package let virtualWorkspace: Bool
        package var dimmed = false
        package var blurred = false
    }
}

package enum PointerActions {
    package static let all: [CursorShortcutSpec] = [
        CursorShortcutSpec(id: "float",
                           action: Action(title: "Toggle Floating", category: .window,
                                          dispatcher: WindowActions.togglefloating.name,
                                          args: "", symbol: "macwindow.on.rectangle"),
                           title: "Float or tile", menuLabel: "Float", actionBefore: "sort ", hint: "Float",
                           selected: { $0.floating }),
        CursorShortcutSpec(id: "zoom",
                           action: Action(title: "Toggle Fullscreen", category: .window,
                                          dispatcher: WindowActions.fullscreen.name,
                                          args: "", symbol: "arrow.up.left.and.arrow.down.right"),
                           title: "Zoom", actionBefore: "sort ", hint: "Full", available: { $0.tiled },
                           selected: { $0.zoomed }),
        CursorShortcutSpec(id: "native",
                           action: Action(title: "Toggle macOS Full Screen", category: .window,
                                          dispatcher: WindowActions.nativefullscreen.name, args: "",
                                          symbol: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"),
                           title: "Native Full Screen", actionBefore: "sort ",
                           hint: "Max", selected: { $0.nativeFullscreen }),
        CursorShortcutSpec(id: "main",
                           action: Action(title: "Swap With Main Window", category: .move,
                                          dispatcher: WindowActions.layoutmsg.name,
                                          args: "swapwithmaster", symbol: "star.square"),
                           title: "Make Main", actionBefore: "swapnext ", available: { $0.canMakeMain }),
        CursorShortcutSpec(id: "layout",
                           action: Action(title: "Next Layout", category: .layout,
                                          dispatcher: WindowActions.cyclelayout.name,
                                          args: "next", symbol: "rectangle.2.swap"),
                           title: "Next Layout", actionBefore: "cyclelayout prev", available: { $0.multipleLayouts }),
        CursorShortcutSpec(id: "display",
                           action: Action(title: "Move Window to Next Display", category: .displays,
                                          dispatcher: WindowActions.movewindow.name, args: "mon:+1",
                                          symbol: "rectangle.portrait.and.arrow.right", focusRequired: true),
                           title: "Send to Next Display", menuDispatcher: WindowActions.movewindowtomonitor.name,
                           menuArgs: "+1",
                           actionBefore: "movewindow mon:-1", available: { $0.multipleDisplays }),
        CursorShortcutSpec(id: "workspace",
                           action: Action(title: "Send Window to Next Workspace", category: .spaces,
                                          dispatcher: WindowActions.movetoworkspacesilent.name, args: "+1",
                                          symbol: "arrow.right.square", focusRequired: true),
                           title: "Send to Next Workspace", includeInActions: false, nextWorkspace: true,
                           available: { $0.virtualWorkspace })
    ] + FocusEffect.all.map(\.pointer) + [
        CursorShortcutSpec(id: "minimize",
                           action: Action(title: "Minimize Window", category: .window,
                                          dispatcher: WindowActions.minimize.name,
                                          args: "", symbol: "minus.square"),
                           title: "Minimize", actionBefore: "sort ", actionOrder: 1, hint: "Min"),
        CursorShortcutSpec(id: "close",
                           action: Action(title: "Close Window", category: .window,
                                          dispatcher: WindowActions.killactive.name,
                                          args: "", symbol: "xmark.square"),
                           title: "Close", actionBefore: "sort ", hint: "Close", destructive: true)
    ]

    package static func hint(_ dispatcher: String) -> String? {
        all.first { $0.hint != nil && $0.dispatcher == dispatcher }?.hint
    }
}
