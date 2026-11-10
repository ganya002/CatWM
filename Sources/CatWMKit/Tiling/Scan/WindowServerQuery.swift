import AppKit

package enum WindowServerQuery {
    package struct WindowInfo {
        package let id: CGWindowID
        package let pid: pid_t
        package let level: Int
        package let bounds: CGRect
    }

    package typealias Membership = [CGWindowID: Set<UInt64>]
    package struct Record {
        package let info: CGWindowInfo?
        package let spaces: Set<UInt64>
    }
    package typealias Records = [CGWindowID: Record]
    private typealias Connection = @convention(c) () -> Int32
    private typealias Query = @convention(c) (Int32, CFArray, UInt64) -> Unmanaged<CFTypeRef>?
    private typealias Copy = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias Advance = @convention(c) (CFTypeRef) -> Bool
    private typealias WindowID = @convention(c) (CFTypeRef) -> CGWindowID
    private typealias SpaceID = @convention(c) (CFTypeRef) -> UInt64
    private typealias Integer = @convention(c) (CFTypeRef) -> Int32
    private typealias Rect = @convention(c) (CFTypeRef) -> CGRect
    private typealias List = @convention(c) (UInt32, CGWindowID) -> Unmanaged<CFArray>?

    private static let connection: Connection? = symbol("SLSMainConnectionID")
    private static let query: Query? = symbol("SLSWindowQueryWindows")
    private static let copyWindows: Copy? = symbol("SLSWindowQueryResultCopyWindows")
    private static let advanceWindow: Advance? = symbol("SLSWindowIteratorAdvance")
    private static let windowID: WindowID? = symbol("SLSWindowIteratorGetWindowID")
    private static let copySpaces: Copy? = symbol("SLSWindowIteratorCopySpaces")
    private static let advanceSpace: Advance? = symbol("SLSSpaceIteratorAdvance")
    private static let spaceID: SpaceID? = symbol("SLSSpaceIteratorGetSpaceID")
    private static let level: Integer? = symbol("SLSWindowIteratorGetLevel")
    private static let pid: Integer? = symbol("SLSWindowIteratorGetPID")
    private static let screenRect: Rect? = symbol("SLSWindowIteratorGetScreenRect")
    private static let listWindows: List? = symbol(
        "CGWindowListCreate", in: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    private static let includeSpaces: UInt64 = 1 << 2

    package static func onScreenWindows() -> [WindowInfo]? {
        guard let ids = WindowServerList.onScreen() ?? windowIDs(.optionOnScreenOnly) else { return nil }
        return metadata(for: ids)
    }

    package static func metadata(for ids: [CGWindowID]) -> [WindowInfo]? {
        guard !ids.isEmpty else { return [] }
        guard let connection, let query, let copyWindows, let advanceWindow, let windowID,
              let level, let pid, let screenRect,
              let result = query(connection(), ids as CFArray, 0)?.takeRetainedValue(),
              let windows = copyWindows(result)?.takeRetainedValue() else { return nil }
        var requested = Set(ids)
        return withExtendedLifetime(result) {
            var found: [WindowInfo] = []
            while advanceWindow(windows) {
                let id = windowID(windows)
                guard requested.remove(id) != nil else { continue }
                found.append(WindowInfo(id: id, pid: pid(windows),
                                        level: Int(level(windows)), bounds: screenRect(windows)))
            }
            return found
        }
    }

    package static func observation(
        known: Set<CGWindowID>, list: (CGWindowListOption) -> [CGWindowID]? = { observationWindowIDs($0) },
        query: (Set<CGWindowID>) -> Records? = records,
        fallback: (CGWindowID) -> [UInt64] = Spaces.of,
        managedSpaces: () -> [UInt64: UInt64]? = { Spaces.snapshot()?.managedSpaceIDs }
    ) -> WindowServerObservation? {
        guard let visible = list([.optionOnScreenOnly, .excludeDesktopElements]),
              let all = list([.optionAll, .excludeDesktopElements]),
              let found = query(known.union(all).union(visible)) else { return nil }
        let windows = visible.compactMap { found[$0]?.info }
        let allWindows = all.compactMap { found[$0]?.info }
        let ids = known.union(allWindows.map(\.id)).union(windows.map(\.id))
        let managed = managedSpaces() ?? [:]
        let spaces = Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, found[id].flatMap { membership($0.spaces, managed: managed) } ?? Set(fallback(id)))
        })
        return WindowServerObservation(windows: windows, allWindows: allWindows, spaces: spaces)
    }

    package static func observationWindowIDs(
        _ options: CGWindowListOption, onScreen: () -> [CGWindowID]? = WindowServerList.onScreen,
        fallback: (CGWindowListOption) -> [CGWindowID]? = windowIDs
    ) -> [CGWindowID]? {
        if options == [.optionOnScreenOnly, .excludeDesktopElements], let ids = onScreen() { return ids }
        return fallback(options)
    }

    package static func memberships(
        for ids: Set<CGWindowID>, query: (Set<CGWindowID>) -> Membership? = batch,
        fallback: (CGWindowID) -> [UInt64] = Spaces.of,
        managedSpaces: () -> [UInt64: UInt64]? = { Spaces.snapshot()?.managedSpaceIDs }
    ) -> Membership {
        guard !ids.isEmpty else { return [:] }
        let found = query(ids) ?? [:]
        let managed = found.isEmpty ? [:] : managedSpaces() ?? [:]
        return Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, found[id].flatMap { membership($0, managed: managed) } ?? Set(fallback(id)))
        })
    }

    private static func membership(_ raw: Set<UInt64>, managed: [UInt64: UInt64]) -> Set<UInt64>? {
        var found = Set<UInt64>()
        for space in raw {
            guard let id = managed[space] else { return nil }
            found.insert(id)
        }
        return found
    }

    package static func frames(for ids: Set<CGWindowID>, query: (Set<CGWindowID>) -> Records? = records)
        -> [CGWindowID: CGRect]? {
        guard !ids.isEmpty else { return [:] }
        return query(ids)?.filter { ids.contains($0.key) }.compactMapValues { $0.info?.bounds }
    }

    private static func batch(_ ids: Set<CGWindowID>) -> Membership? {
        records(ids)?.mapValues(\.spaces)
    }

    private static func windowIDs(_ options: CGWindowListOption) -> [CGWindowID]? {
        guard let listWindows, let list = listWindows(options.rawValue, kCGNullWindowID)?.takeRetainedValue() else {
            return nil
        }
        var ids: [CGWindowID] = []
        ids.reserveCapacity(CFArrayGetCount(list))
        for index in 0..<CFArrayGetCount(list) {
            let raw = UInt(bitPattern: CFArrayGetValueAtIndex(list, index))
            guard let id = CGWindowID(exactly: raw) else { return nil }
            ids.append(id)
        }
        return ids
    }

    private static func records(_ ids: Set<CGWindowID>) -> Records? {
        if ids.isEmpty { return [:] }
        guard let connection, let query, let copyWindows, let advanceWindow, let windowID,
              let copySpaces, let advanceSpace, let spaceID, let level, let pid, let screenRect,
              let result = query(connection(), Array(ids) as CFArray, includeSpaces)?.takeRetainedValue(),
              let windows = copyWindows(result)?.takeRetainedValue() else { return nil }
        return withExtendedLifetime(result) {
            var found: Records = [:]
            while advanceWindow(windows) {
                let id = windowID(windows)
                guard ids.contains(id) else { continue }
                guard let spaces = copySpaces(windows)?.takeRetainedValue() else { return nil }
                var membership = Set<UInt64>()
                while advanceSpace(spaces) { membership.insert(spaceID(spaces)) }
                let info = level(windows) == 0
                    ? CGWindowInfo(id: id, pid: pid(windows), bounds: screenRect(windows)) : nil
                found[id] = Record(info: info, spaces: membership)
            }
            return found
        }
    }
}

package struct WindowServerObservation {
    package var windows: [CGWindowInfo] = []
    package var allWindows: [CGWindowInfo] = []
    package var spaces: [CGWindowID: Set<UInt64>] = [:]

    package func keeping(_ keep: (pid_t) -> Bool) -> Self {
        Self(windows: windows.filter { keep($0.pid) }, allWindows: allWindows.filter { keep($0.pid) }, spaces: spaces)
    }

    package static func read(known: Set<CGWindowID>) -> Self {
        dispatchPrecondition(condition: .notOnQueue(.main))
        if let observation = WindowServerQuery.observation(known: known) { return observation }
        let windows = CGWindowInfo.onScreen()
        let all = CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements])
        let ids = known.union(all.map(\.id))
        return Self(windows: windows, allWindows: all,
                    spaces: WindowServerQuery.memberships(for: ids))
    }
}
