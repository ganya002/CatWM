import AppKit
import CatWMKit
import MacKeysCore
import MacKeysUI
import SwiftUI

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
    init(_ action: ConfigDocument.KeyAction) {
        self.init(code: action.code, dispatcher: action.row.dispatcher, arg: action.arg, title: action.title)
    }
    init(_ bind: KeyBinding) {
        let match = Actions.match(BindRow(mods: "", key: "", dispatcher: bind.dispatcher, args: bind.arg))
        let title = bind.dispatcher == "exec" ? (bind.arg.isEmpty ? "Run Command" : "Run “\(bind.arg)”")
            : match?.title ?? "\(bind.dispatcher) \(bind.arg)".trimmingCharacters(in: .whitespaces)
        self.init(code: bind.keyCode, dispatcher: bind.dispatcher, arg: bind.arg, title: title)
    }

    static func normalized(_ dispatcher: String, _ arg: String) -> (command: String, argument: String) {
        var command = dispatcher.lowercased(), argument = arg.trimmingCharacters(in: .whitespaces).lowercased()
        if command == "swapwindow" { command = "movewindow" }
        if command == "movewindowtomonitor" { command = "movewindow"; argument = "mon:" + argument }
        if command == "setlayout" { command = "layout" }
        if command == "layoutmsg" {
            switch argument {
            case "cyclenext": command = "cyclenext"; argument = ""
            case "cycleprev": command = "cyclenext"; argument = "prev"
            case "swapnext": command = "swapnext"; argument = ""
            case "swapprev": command = "swapnext"; argument = "prev"
            case "orientationnext": command = "cyclelayout"; argument = "next"
            case "orientationprev": command = "cyclelayout"; argument = "prev"
            default:
                if argument.hasPrefix("mfact") {
                    command = "splitratio"
                    argument = String(argument.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return (command, argument)
    }

    static func label(dispatcher: String, arg: String) -> String {
        let (command, argument) = normalized(dispatcher, arg)
        if let hint = PointerActions.hint(command) { return hint }
        let arrows = Direction.hintArrows
        let back = ["prev", "-", "e-", "r-", "m-"].contains { argument.hasPrefix($0) }
        func screen(_ target: String) -> String {
            if let arrow = arrows[target] { return "Screen \(arrow)" }
            return target.hasPrefix("-") ? "‹ Screen" : "Screen ›"
        }
        switch command {
        case "movefocus": return arrows[argument] ?? "Focus"
        case "movewindow":
            return argument.hasPrefix("mon:") ? screen(String(argument.dropFirst(4))) : arrows[argument] ?? "Move"
        case "focusmonitor": return screen(argument)
        case "cyclenext": return back ? "‹ Cycle" : "Cycle"
        case "swapnext": return back ? "‹ Swap" : "Swap ›"
        case "workspace", "movetoworkspace", "movetoworkspacesilent":
            if let number = Int(argument) { return "\(number)" }
            if argument == "previous" { return "Back" }
            return back ? "‹ Prev" : "Next ›"
        case "cyclelayout": return back ? "‹ Layout" : "Layout ›"
        case "layout": return Layout(rawValue: argument)?.title ?? argument.capitalized
        case "splitratio": return argument.hasPrefix("-") ? "Main −" : "Main +"
        case "layoutmsg":
            switch argument {
            case "swapwithmaster": return "Swap"
            case "swapsides": return "Sides"
            case "focusmaster": return "Main"
            case "addmaster": return "Mains +"
            case "removemaster": return "Mains −"
            default: return "Layout"
            }
        case "retile", "reevaluate": return "Retile"
        case "toggletiling": return "Tiling"
        case "reload": return "Reload"
        case "exec": return "Run"
        case "exit": return "Quit"
        case "sethomespace": return "Home"
        case "switcher": return back ? "‹ Switch" : "Switch"
        case "submap": return argument == "reset" ? "Exit" : argument.capitalized
        default:
            var name = Substring(command)
            for prefix in ["toggle", "move", "focus", "set"] where name.hasPrefix(prefix) && name.count > prefix.count {
                name = name.dropFirst(prefix.count)
                break
            }
            return String(name.prefix(7)).capitalized
        }
    }
}
