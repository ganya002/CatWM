import Foundation

#if CATWM_RESIZE_PROBE
enum Log {
    static func info(_ message: @autoclosure () -> String) { fputs(message() + "\n", stderr) }
    static func debug(_ message: @autoclosure () -> String) { info(message()) }
    static func attempt(_ action: String, _ body: () throws -> Void) {
        do { try body() } catch { info("\(action): \(error)") }
    }
}
#endif
