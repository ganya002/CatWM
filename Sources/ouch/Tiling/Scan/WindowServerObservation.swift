import AppKit

struct WindowServerObservation {
    var windows: [CGWindowInfo] = []
    var spaces: [CGWindowID: Set<UInt64>] = [:]

    static func read(known: Set<CGWindowID>) -> Self {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let windows = CGWindowInfo.onScreen()
        let ids = known.union(windows.map(\.id))
        return Self(windows: windows,
                    spaces: Dictionary(uniqueKeysWithValues: ids.map { ($0, Set(Spaces.of(window: $0))) }))
    }
}
