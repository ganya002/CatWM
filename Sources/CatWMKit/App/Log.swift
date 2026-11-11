import Foundation
import os

package enum Log {
    package static let url = NSClassFromString("XCTestCase") == nil
        ? Instance.logURL
        : FileManager.default.temporaryDirectory.appendingPathComponent("CatWM-test-\(getpid()).log")
    package static let verboseLaunch = LaunchFlag.verbose.isSet

    package static let maxSize = 2_000_000
    package static let keptSize = 500_000

    private struct FileState {
        var launchOffset: UInt64
        var size: UInt64
        var verbose = false
    }

    private final class File: Sendable {
        let handle: FileHandle?
        let state: OSAllocatedUnfairLock<FileState>

        init() {
            let fileManager = FileManager.default
            if let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize,
               let data = fileManager.contents(atPath: url.path) {
                try? tail(of: data).write(to: url)
            }
            if !fileManager.fileExists(atPath: url.path) { fileManager.createFile(atPath: url.path, contents: nil) }
            let handle = try? FileHandle(forWritingTo: url)
            let offset = (try? handle?.seekToEnd()) ?? 0
            self.handle = handle
            state = OSAllocatedUnfairLock(initialState: FileState(launchOffset: offset, size: offset))
        }
    }

    private static let file = File()

    package static var verbose: Bool {
        get { file.state.withLock { $0.verbose } }
        set { file.state.withLock { $0.verbose = newValue } }
    }

    package static func tail(of data: Data) -> Data {
        guard data.count > keptSize else { return data }
        let tail = data.suffix(keptSize)
        let start = tail.firstIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? tail.startIndex
        return Data(tail[start...])
    }

    package static func beforeLaunch() -> String {
        let offset = file.state.withLock { $0.launchOffset }
        guard let data = FileManager.default.contents(atPath: url.path) else { return "" }
        return String(decoding: data.prefix(Int(offset)), as: Unicode.UTF8.self)
    }

    private static func time() -> String {
        var now = timespec()
        clock_gettime(CLOCK_REALTIME, &now)
        var seconds = now.tv_sec
        var parts = tm()
        localtime_r(&seconds, &parts)
        return String(format: "%02d:%02d:%02d.%03d", parts.tm_hour, parts.tm_min, parts.tm_sec, now.tv_nsec / 1_000_000)
    }

    package static func info(_ message: @autoclosure () -> String) { write(message()) }
    package static func debug(_ message: @autoclosure () -> String) { if verbose { write(message()) } }

    package static func attempt(_ action: String, _ body: () throws -> Void) {
        do { try body() } catch { info("\(action) failed: \(error)") }
    }

    private static func write(_ message: String) {
        let line = Data("\(time()) \(message)\n".utf8)
        guard let handle = file.handle else { return }
        file.state.withLock { state in
            if state.size > UInt64(maxSize) { trim(handle, &state) }
            try? handle.write(contentsOf: line)
            state.size += UInt64(line.count)
        }
    }

    private static func trim(_ handle: FileHandle, _ state: inout FileState) {
        guard let data = FileManager.default.contents(atPath: url.path) else { return }
        let kept = tail(of: data)
        try? handle.truncate(atOffset: 0)
        try? handle.write(contentsOf: kept)
        let removed = UInt64(data.count - kept.count)
        state.launchOffset = state.launchOffset > removed ? state.launchOffset - removed : 0
        state.size = UInt64(kept.count)
    }
}
