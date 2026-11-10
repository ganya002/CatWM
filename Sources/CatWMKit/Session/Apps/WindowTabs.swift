import CoreGraphics

package enum WindowTabs {
    package static func background(_ windows: [AppStateCapture.Window],
                                   onScreen: Set<CGWindowID>) -> [CGWindowID: CGWindowID] {
        var result: [CGWindowID: CGWindowID] = [:]
        for hidden in windows where !onScreen.contains(hidden.id) {
            let visible = windows.first {
                $0.id != hidden.id && onScreen.contains($0.id) && $0.bundleID == hidden.bundleID
                    && sameFrame($0.frame, hidden.frame)
            }
            if let visible { result[hidden.id] = visible.id }
        }
        return result
    }

    package static func merged(_ windows: [ScriptedWindow]) -> [ScriptedWindow] {
        var result: [ScriptedWindow] = []
        for window in windows {
            guard let frame = window.frame,
                  let index = result.firstIndex(where: { $0.frame.map { sameFrame($0, frame) } ?? false }) else {
                result.append(window)
                continue
            }
            let tabs = result[index].state.tabs + window.state.tabs
            result[index].state = AppState(tabs: tabs, selected: result[index].state.selected)
        }
        return result
    }

    package static func sameFrame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
    }
}
