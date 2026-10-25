import CoreGraphics

struct WindowScope: Equatable {
    let pids: Set<pid_t>
    let display: String?

    init(pids: Set<pid_t>, display: String? = nil) {
        self.pids = pids
        self.display = display
    }

    init?(_ text: String) {
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

    func filter(_ observation: WindowServerObservation) -> WindowServerObservation {
        var observation = observation
        observation.windows.removeAll { !pids.contains($0.pid) }
        observation.allWindows.removeAll { !pids.contains($0.pid) }
        return observation
    }

    func filter(_ applications: [RunningApplicationSnapshot]) -> [RunningApplicationSnapshot] {
        applications.filter { pids.contains($0.pid) }
    }

    func filter(_ screens: [Screen]) -> [Screen] {
        guard let display else { return screens }
        return screens.filter { $0.uuid == display }
    }

    func restrict(_ config: Config) -> Config {
        var config = config
        config.virtualWorkspaces = false
        config.focusFollowsMouse = false
        config.mouseFollowsFocus = false
        config.cursorActions = false
        config.dimOtherWindows = false
        config.blurOtherWindows = false
        return config
    }

    func allows(_ dispatcher: String) -> Bool { !Self.refusedDispatchers.contains(dispatcher) }

    static let allowedDispatchers: Set<String> = [
        "movefocus", "cyclenext", "movewindow", "movewindowtomonitor", "swapwindow", "swapnext",
        "togglefloating", "fullscreen", "minimize", "killactive",
        "moveintogroup", "moveoutofgroup", "changegroupactive", "movegroupwindow",
        "layoutmsg", "splitratio", "cyclelayout", "layout", "toggletiling", "retile",
        "submap", "reload", "exit"
    ]

    static let refusedDispatchers: Set<String> = [
        "nativefullscreen", "focusmonitor", "workspace", "movetoworkspace", "movetoworkspacesilent", "sethomespace",
        "sort", "sort-undo", "switcher", "exec", "launch", "toggledim", "toggleblur"
    ]
}

struct GlobalInput: Equatable {
    let keys: Bool
    let capsLock: Bool
    let mouseTaps: Bool

    init(scope: WindowScope?, keys: String?) {
        self.keys = scope == nil || keys == "on"
        capsLock = scope == nil
        mouseTaps = scope == nil
    }
}
