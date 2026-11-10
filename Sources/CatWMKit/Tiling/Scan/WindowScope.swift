import CoreGraphics

package struct WindowScope: Equatable {
    package let pids: Set<pid_t>
    package let display: String?

    package init(pids: Set<pid_t>, display: String? = nil) {
        self.pids = pids
        self.display = display
    }

    package init?(_ text: String) {
        var pids: Set<pid_t>?
        var display: String?
        for part in text.split(separator: ";", omittingEmptySubsequences: false) {
            let pair = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            switch pair[0] {
            case "pids" where pids == nil:
                let parts = pair[1].split(separator: ",", omittingEmptySubsequences: false)
                let list = parts.compactMap { pid_t($0) }.filter { $0 > 0 }
                guard list.count == parts.count else { return nil }
                pids = Set(list)
            case "display" where display == nil && !pair[1].isEmpty:
                display = String(pair[1])
            default:
                return nil
            }
        }
        guard let pids, !pids.isEmpty else { return nil }
        self.init(pids: pids, display: display)
    }

    package var text: String {
        "pids:" + pids.sorted().map(String.init).joined(separator: ",") + (display.map { ";display:\($0)" } ?? "")
    }

    package func filter(_ screens: [Screen]) -> [Screen] {
        guard let display else { return screens }
        return screens.filter { $0.uuid == display }
    }

    package func restrict(_ config: Config) -> Config {
        var config = config
        config.virtualWorkspaces = false
        config.focusFollowsMouse = false
        config.mouseFollowsFocus = false
        config.cursorActions = false
        config.dimOtherWindows = false
        config.blurOtherWindows = false
        config.bindings.removeAll { !allows($0.dispatcher) }
        return config
    }

    package func allows(_ command: String) -> Bool {
        !Self.refusedCommands.contains(WindowActions.named(command)?.name ?? command)
    }

    package static let allowedCommands: Set<String> = [
        "ping", "commands", "dispatch", "subscribe", "unsubscribe",
        "status", "windows", "workspaces", "screens", "dump", "config.get", "config.set", "config.options",
        "poststyle",
        "movefocus", "cyclenext", "movewindow", "movewindowtomonitor", "swapwindow", "swapnext",
        "togglefloating", "fullscreen", "minimize", "killactive",
        "moveintogroup", "moveoutofgroup", "changegroupactive", "movegroupwindow",
        "layoutmsg", "splitratio", "cyclelayout", "layout", "toggletiling", "retile",
        "reload", "exit"
    ]

    package static let refusedCommands: Set<String> = [
        "nativefullscreen", "focusmonitor", "workspace", "movetoworkspace", "movetoworkspacesilent", "sethomespace",
        "sort", "sort-undo", "switcher", "exec", "launch", "toggledim", "toggleblur",
        "grabtest", "modefx", "panelfx", "intro", "introlab", "submap"
    ]
}

package struct GlobalInput: Equatable {
    package let keys: Bool
    package let capsLock: Bool
    package let mouseTaps: Bool
    package let pointerAndFocus: Bool

    package init(scope: WindowScope?, keys: String?, embedded: Bool = false) {
        self.keys = scope == nil || keys == "on" || embedded
        capsLock = scope == nil && !embedded
        mouseTaps = scope == nil
        pointerAndFocus = scope == nil
    }
}
