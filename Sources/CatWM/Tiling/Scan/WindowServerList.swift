import AppKit

enum WindowServerList {
    private typealias Connection = @convention(c) () -> Int32
    private typealias List = @convention(c) (
        Int32, Int32, Int32, UnsafeMutablePointer<CGWindowID>, UnsafeMutablePointer<Int32>
    ) -> Int32
    private static let connection: Connection? = symbol("SLSMainConnectionID")
    private static let list: List? = symbol("SLSGetOnScreenWindowList")

    static func onScreen() -> [CGWindowID]? {
        guard let connection else { return nil }
        return onScreen(connection: connection())
    }

    static func onScreen(connection cid: Int32) -> [CGWindowID]? {
        guard let list else { return nil }
        return read(capacity: 1_024) { buffer in
            var returned: Int32 = 0
            guard let base = buffer.baseAddress,
                  list(cid, 0, Int32(buffer.count), base, &returned) == 0 else { return nil }
            return returned
        }
    }

    static func read(capacity: Int32, fill: (UnsafeMutableBufferPointer<CGWindowID>) -> Int32?) -> [CGWindowID]? {
        guard capacity > 0, capacity < 65_536 else { return nil }
        var windows = Array(repeating: CGWindowID(0), count: Int(capacity))
        return windows.withUnsafeMutableBufferPointer { buffer in
            guard let returned = fill(buffer), returned > 0, returned < buffer.count else { return nil }
            let ids = Array(buffer.prefix(Int(returned)))
            guard !ids.contains(0), Set(ids).count == ids.count else { return nil }
            return ids
        }
    }
}
