import AppKit
import CatWMKit

enum OverlaySpace {
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias CreateFn = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias LevelFn = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowFn = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddFn = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    private static let skylight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let conn: ConnFn? = symbol("SLSMainConnectionID", in: skylight)
    private static let create: CreateFn? = symbol("SLSSpaceCreate", in: skylight)
    private static let setLevel: LevelFn? = symbol("SLSSpaceSetAbsoluteLevel", in: skylight)
    private static let show: ShowFn? = symbol("SLSShowSpaces", in: skylight)
    private static let add: AddFn? = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", in: skylight)

    private static let space: UInt64? = {
        guard let conn, let create, let setLevel, let show else { return nil }
        let cid = conn()
        let space = create(cid, 1, nil)
        guard space != 0 else { return nil }
        _ = setLevel(cid, space, Int32.max)
        _ = show(cid, [space] as CFArray)
        return space
    }()

    static func add(_ window: NSWindow) {
        guard let conn, let add, let space, window.windowNumber > 0 else { return }
        _ = add(conn(), space, [window.windowNumber] as CFArray, 7)
    }
}
