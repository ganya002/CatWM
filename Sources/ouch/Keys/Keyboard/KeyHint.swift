import AppKit
import SwiftUI
import MacKeysCore
import MacKeysUI

struct KeyHint: Identifiable, Equatable {
    let code: UInt16
    let dispatcher: String
    let arg: String
    let title: String
    var id: UInt16 { code }

    var group: KeyGroup { KeyGroup(dispatcher: dispatcher, arg: arg) }
    var label: String { Self.label(dispatcher: dispatcher, arg: arg) }

    init(code: UInt16, dispatcher: String, arg: String, title: String) {
        self.code = code
        self.dispatcher = dispatcher
        self.arg = arg
        self.title = title
    }
    init(_ a: ConfigDocument.KeyAction) {
        self.init(code: a.code, dispatcher: a.row.dispatcher, arg: a.arg, title: a.title)
    }
    init(_ b: KeyBinding) {
        let match = Actions.match(BindRow(mods: "", key: "", dispatcher: b.dispatcher, args: b.arg))
        let title = b.dispatcher == "exec" ? (b.arg.isEmpty ? "Run Command" : "Run “\(b.arg)”")
            : match?.title ?? "\(b.dispatcher) \(b.arg)".trimmingCharacters(in: .whitespaces)
        self.init(code: b.keyCode, dispatcher: b.dispatcher, arg: b.arg, title: title)
    }

    static func normalized(_ dispatcher: String, _ arg: String) -> (d: String, a: String) {
        var d = dispatcher.lowercased(), a = arg.trimmingCharacters(in: .whitespaces).lowercased()
        if d == "swapwindow" { d = "movewindow" }
        if d == "movewindowtomonitor" { d = "movewindow"; a = "mon:" + a }
        if d == "setlayout" { d = "layout" }
        if d == "layoutmsg" {
            switch a {
            case "cyclenext": d = "cyclenext"; a = ""
            case "cycleprev": d = "cyclenext"; a = "prev"
            case "swapnext": d = "swapnext"; a = ""
            case "swapprev": d = "swapnext"; a = "prev"
            case "orientationnext": d = "cyclelayout"; a = "next"
            case "orientationprev": d = "cyclelayout"; a = "prev"
            default: if a.hasPrefix("mfact") { d = "splitratio"; a = String(a.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            }
        }
        return (d, a)
    }

    static func label(dispatcher: String, arg: String) -> String {
        let (d, a) = normalized(dispatcher, arg)
        let arrows = ["l": "←", "r": "→", "u": "↑", "d": "↓", "left": "←", "right": "→", "up": "↑", "down": "↓"]
        let back = a.hasPrefix("prev") || a.hasPrefix("-") || a.hasPrefix("e-")
        func screen(_ s: String) -> String {
            if let arrow = arrows[s] { return "Screen \(arrow)" }
            return s.hasPrefix("-") ? "‹ Screen" : "Screen ›"
        }
        switch d {
        case "movefocus": return arrows[a] ?? "Focus"
        case "movewindow": return a.hasPrefix("mon:") ? screen(String(a.dropFirst(4))) : arrows[a] ?? "Move"
        case "focusmonitor": return screen(a)
        case "cyclenext": return back ? "‹ Cycle" : "Cycle"
        case "swapnext": return back ? "‹ Swap" : "Swap ›"
        case "workspace", "movetoworkspace", "movetoworkspacesilent":
            if let n = Int(a) { return "\(n)" }
            if a == "previous" { return "Back" }
            return back ? "‹ Prev" : "Next ›"
        case "cyclelayout": return back ? "‹ Layout" : "Layout ›"
        case "layout": return Layout(rawValue: a)?.title ?? a.capitalized
        case "splitratio": return a.hasPrefix("-") ? "Main −" : "Main +"
        case "layoutmsg":
            switch a {
            case "swapwithmaster": return "Swap"
            case "focusmaster": return "Main"
            case "addmaster": return "Mains +"
            case "removemaster": return "Mains −"
            default: return "Layout"
            }
        case "fullscreen": return "Full"
        case "nativefullscreen": return "Max"
        case "togglefloating": return "Float"
        case "retile", "reevaluate": return "Retile"
        case "toggletiling": return "Tiling"
        case "toggledim": return "Dim"
        case "toggleblur": return "Blur"
        case "reload": return "Reload"
        case "killactive": return "Close"
        case "minimize": return "Min"
        case "exec": return "Run"
        case "exit": return "Quit"
        case "sethomespace": return "Home"
        case "submap": return a == "reset" ? "Exit" : a.capitalized
        default:
            var name = Substring(d)
            for prefix in ["toggle", "move", "focus", "set"] where name.hasPrefix(prefix) && name.count > prefix.count {
                name = name.dropFirst(prefix.count)
                break
            }
            return String(name.prefix(7)).capitalized
        }
    }
}
