import AppKit
import ApplicationServices

package enum Spaces {
    package static var canMoveWindows: Bool {
        _ = conn?()
        return NativeSpaceMove.isAvailable
    }

    package static func move(window id: CGWindowID, to target: UInt64, waitUntilOnScreen: Bool = false,
                             completion: @escaping (Bool) -> Void) {
        guard target != 0, canMoveWindows else { completion(false); return }
        let move = WindowSpaceMove(
            membership: { of(window: id) }, submit: { NativeSpaceMove.move(window: id, to: target) },
            isOnScreen: {
                let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
                return info?.first?[kCGWindowIsOnscreen as String] as? Bool == true
            })
        move.run(to: target, waitUntilOnScreen: waitUntilOnScreen, completion: completion)
    }

    private typealias ConnFn = @convention(c) () -> Int32
    private typealias SpaceFn = @convention(c) (Int32, CFString) -> UInt64
    private static let skylight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let conn: ConnFn? = symbol("SLSMainConnectionID", in: skylight)
    private static let space: SpaceFn? = symbol("SLSManagedDisplayGetCurrentSpace", in: skylight)

    private typealias CopySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let copySpaces: CopySpacesFn? = symbol("SLSCopyManagedDisplaySpaces", in: skylight)

    package struct DisplaySpaces {
        package let ids: [UInt64]
        package let desktops: [Int]
        package let current: Int?
        package var uuids: [String?] = []
    }

    package struct Snapshot {
        package let displays: [[String: Any]]

        package var managedSpaceIDs: [UInt64: UInt64] {
            var found: [UInt64: UInt64] = [:]
            func add(_ space: [String: Any], parent: UInt64? = nil) {
                guard let managed = space["ManagedSpaceID"] as? UInt64 ?? parent, managed != 0 else { return }
                found[managed] = managed
                if let raw = space["id64"] as? UInt64, raw != 0 { found[raw] = managed }
            }
            for display in displays {
                for space in display["Spaces"] as? [[String: Any]] ?? [] {
                    add(space)
                    let parent = space["ManagedSpaceID"] as? UInt64
                    if let wall = space["WallSpace"] as? [String: Any] { add(wall, parent: parent) }
                    let layout = space["TileLayoutManager"] as? [String: Any]
                    for tile in layout?["TileSpaces"] as? [[String: Any]] ?? [] { add(tile, parent: parent) }
                }
            }
            return found
        }

        package func list(display uuid: String) -> DisplaySpaces? {
            let entry = displays.first { ($0["Display Identifier"] as? String) == uuid }
                ?? (displays.count == 1 ? displays[0] : nil)
            guard let entry, let spaces = entry["Spaces"] as? [[String: Any]] else { return nil }
            let ids = spaces.map { ($0["ManagedSpaceID"] as? UInt64) ?? 0 }
            let desktops = spaces.indices.filter { (spaces[$0]["type"] as? Int ?? 0) == 0 }
            let current = (entry["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? UInt64
            return DisplaySpaces(ids: ids, desktops: desktops, current: current.flatMap { ids.firstIndex(of: $0) },
                                 uuids: spaces.map { ($0["uuid"] as? String).flatMap { $0.isEmpty ? nil : $0 } })
        }
    }

    package static func snapshot() -> Snapshot? {
        guard let conn, let copySpaces,
              let arr = copySpaces(conn())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return Snapshot(displays: arr)
    }

    package static func list(display uuid: String) -> DisplaySpaces? { snapshot()?.list(display: uuid) }

    package static func isFullscreen(display uuid: String) -> Bool {
        guard let spaces = list(display: uuid), let cur = spaces.current else { return false }
        return !spaces.desktops.contains(cur)
    }

    private typealias WindowSpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let windowSpaces: WindowSpacesFn? = symbol("SLSCopySpacesForWindows", in: skylight)

    package static func of(window id: CGWindowID) -> [UInt64] {
        guard let conn, let windowSpaces,
              let arr = windowSpaces(conn(), 0x7, [id] as CFArray)?.takeRetainedValue() as? [UInt64]
        else { return [] }
        return arr
    }

    package static func current(display uuid: String) -> UInt64 {
        guard let conn, let space else { return 0 }
        return space(conn(), uuid as CFString)
    }
}

package enum SystemShortcut {
    package struct Combo { package let keyCode: UInt16; package let flags: CGEventFlags }

    private static func read(_ id: Int) -> (enabled: Bool, combo: Combo)? {
        guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
                .dictionary(forKey: "AppleSymbolicHotKeys"), // style-ok: a system preference key, not ours
              let entry = all[String(id)] as? [String: Any] else { return nil }
        let enabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int).map { $0 != 0 } ?? false)
        guard let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count == 3
        else { return nil }
        return (enabled, Combo(keyCode: UInt16(truncatingIfNeeded: params[1]),
                               flags: CGEventFlags(rawValue: UInt64(truncatingIfNeeded: params[2]))))
    }

    package static func desktop(_ number: Int) -> Combo? {
        guard (1...16).contains(number), let shortcut = read(117 + number), shortcut.enabled else { return nil }
        return shortcut.combo
    }

    package static func step(right: Bool) -> Combo? {
        if let shortcut = read(right ? 81 : 79) { return shortcut.enabled ? shortcut.combo : nil }
        return Combo(keyCode: right ? 124 : 123, flags: [.maskControl, .maskSecondaryFn])
    }
}
