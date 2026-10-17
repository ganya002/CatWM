import AppKit
import ApplicationServices

enum Spaces {
    static var canMoveWindows: Bool {
        _ = conn?()
        return NativeSpaceMove.isAvailable
    }

    static func move(window id: CGWindowID, to target: UInt64, waitUntilOnScreen: Bool = false,
                     completion: @escaping (Bool) -> Void) {
        guard target != 0, canMoveWindows else { completion(false); return }
        if of(window: id) == [target] { completion(true); return }
        guard NativeSpaceMove.move(window: id, to: target) else { completion(false); return }
        let deadline = Date().addingTimeInterval(0.5)
        func check() {
            if of(window: id) == [target] {
                let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
                if !waitUntilOnScreen || info?.first?[kCGWindowIsOnscreen as String] as? Bool == true {
                    completion(true)
                    return
                }
            }
            guard Date() < deadline else { completion(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: check)
        }
        check()
    }

    private typealias ConnFn = @convention(c) () -> Int32
    private typealias SpaceFn = @convention(c) (Int32, CFString) -> UInt64
    private static let skylight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let conn: ConnFn? = symbol("SLSMainConnectionID", in: skylight)
    private static let space: SpaceFn? = symbol("SLSManagedDisplayGetCurrentSpace", in: skylight)

    private typealias CopySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let copySpaces: CopySpacesFn? = symbol("SLSCopyManagedDisplaySpaces", in: skylight)

    struct DisplaySpaces {
        let ids: [UInt64]
        let desktops: [Int]
        let current: Int?
    }

    static func list(display uuid: String) -> DisplaySpaces? {
        guard let conn, let copySpaces, let arr = copySpaces(conn())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let entry = arr.first { ($0["Display Identifier"] as? String) == uuid } ?? (arr.count == 1 ? arr[0] : nil)
        guard let entry, let spaces = entry["Spaces"] as? [[String: Any]] else { return nil }
        let ids = spaces.map { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? 0 }
        let desktops = spaces.indices.filter { (spaces[$0]["type"] as? Int ?? 0) == 0 }
        let cur = ((entry["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
        return DisplaySpaces(ids: ids, desktops: desktops, current: cur.flatMap { ids.firstIndex(of: $0) })
    }

    static func isFullscreen(display uuid: String) -> Bool {
        guard let s = list(display: uuid), let cur = s.current else { return false }
        return !s.desktops.contains(cur)
    }

    private typealias WindowSpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let windowSpaces: WindowSpacesFn? = symbol("SLSCopySpacesForWindows", in: skylight)

    static func of(window id: CGWindowID) -> [UInt64] {
        guard let conn, let windowSpaces,
              let arr = windowSpaces(conn(), 0x7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return [] }
        return arr.map(\.uint64Value)
    }

    static func current(display uuid: String) -> UInt64 {
        guard let conn, let space else { return 0 }
        return space(conn(), uuid as CFString)
    }
}
