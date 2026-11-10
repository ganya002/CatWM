import AppKit

package enum DesktopMenuBarNative {
    package struct WindowInfo {
        package let id: CGWindowID
        package let level: Int32
        package let owner: Int32
        package let frame: CGRect
    }
    private typealias Connection = @convention(c) () -> Int32
    private typealias Windows = @convention(c) (
        Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?
    private typealias Read = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<Int32>) -> Int32
    private typealias Rect = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<CGRect>) -> Int32
    private typealias Theme = @convention(c) (UInt64) -> Int32
    private typealias Alpha = @convention(c) (Int32, UInt64, Float) -> Int32
    private static let connection: Connection? = symbol("SLSMainConnectionID")
    private static let copy: Windows? = symbol("SLSCopyWindowsWithOptionsAndTags")
    private static let level: Read? = symbol("SLSGetWindowLevel")
    private static let owner: Read? = symbol("SLSGetWindowOwner")
    private static let rect: Rect? = symbol("SLSGetScreenRectForWindow")
    private static let appearance: Theme? = symbol("SLSGetMenuAppearanceThemeOnSpace")
    private static let setAlpha: Alpha? = symbol("SLSSetMenuBarSystemOverrideAlpha")
    private typealias Order = @convention(c) (Int32, CGWindowID, Int32, CGWindowID) -> Int32
    private static let order: Order? = symbol("SLSOrderWindow")

    package static func orderOut(_ window: CGWindowID) {
        guard let connection, let order else { return }
        _ = order(connection(), window, 0, 0)
    }

    package static func theme(_ space: UInt64) -> Int32? { appearance?(space) }

    @discardableResult package static func alpha(_ space: UInt64, _ value: Float) -> Bool {
        guard let connection, let setAlpha else { return false }
        return setAlpha(connection(), space, value) == 0
    }

    package static func windows(on space: UInt64, levels: Set<Int32>? = nil) -> [WindowInfo] {
        guard let connection, let copy else { return [] }
        var set: UInt64 = 0, clear: UInt64 = 0
        let ids = copy(connection(), 0, [space] as CFArray, 0x7, &set, &clear)?.takeRetainedValue()
            as? [CGWindowID] ?? []
        guard let metadata = WindowServerQuery.metadata(for: ids) else {
            return ids.compactMap { info($0, levels: levels) }
        }
        let found = Dictionary(metadata.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { id in
            guard let window = found[id] else { return info(id, levels: levels) }
            guard levels?.contains(Int32(window.level)) ?? true else { return nil }
            var windowOwner: Int32 = 0
            guard let owner, owner(connection(), id, &windowOwner) == 0 else { return nil }
            return WindowInfo(id: id, level: Int32(window.level), owner: windowOwner, frame: window.bounds)
        }
    }

    package static func info(_ id: CGWindowID) -> WindowInfo? {
        info(id, levels: nil)
    }

    private static func info(_ id: CGWindowID, levels: Set<Int32>?) -> WindowInfo? {
        guard let connection, let level, let owner, let rect else { return nil }
        let cid = connection()
        var windowLevel: Int32 = 0, windowOwner: Int32 = 0, frame = CGRect.zero
        guard level(cid, id, &windowLevel) == 0, levels?.contains(windowLevel) ?? true,
              owner(cid, id, &windowOwner) == 0,
              rect(cid, id, &frame) == 0 else { return nil }
        return WindowInfo(id: id, level: windowLevel, owner: windowOwner, frame: frame)
    }
}
