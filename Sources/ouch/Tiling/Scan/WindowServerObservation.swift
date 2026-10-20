import AppKit

struct WindowServerObservation {
    var windows: [CGWindowInfo] = []
    var allWindows: [CGWindowInfo] = []
    var spaces: [CGWindowID: Set<UInt64>] = [:]

    static func read(known: Set<CGWindowID>) -> Self {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let windows = CGWindowInfo.onScreen()
        let all = CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements])
        let ids = known.union(all.map(\.id))
        return Self(windows: windows, allWindows: all,
                    spaces: Dictionary(uniqueKeysWithValues: ids.map { ($0, Set(Spaces.of(window: $0))) }))
    }
}
