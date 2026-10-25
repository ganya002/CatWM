import Foundation
import os

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CatWM.log")
    private static let verboseFlag = OSAllocatedUnfairLock(initialState: false)
    static var verbose: Bool {
        get { verboseFlag.withLock { $0 } }
        set { verboseFlag.withLock { $0 = newValue } }
    }
    static let verboseLaunch = CommandLine.arguments.contains("--verbose")

    static let maxSize = 2_000_000
    static let keptSize = 500_000

    private struct Extent { var launchOffset: UInt64 = 0, size: UInt64 = 0 }
    private static let extent = OSAllocatedUnfairLock(initialState: Extent())

    private static let handle: FileHandle? = {
        let fileManager = FileManager.default
        if let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize,
           let data = fileManager.contents(atPath: url.path) {
            try? tail(of: data).write(to: url)
        }
        if !fileManager.fileExists(atPath: url.path) { fileManager.createFile(atPath: url.path, contents: nil) }
        let fileHandle = try? FileHandle(forWritingTo: url)
        let end = (try? fileHandle?.seekToEnd()) ?? 0
        extent.withLock { $0 = Extent(launchOffset: end, size: end) }
        return fileHandle
    }()

    static func tail(of data: Data) -> Data {
        guard data.count > keptSize else { return data }
        let tail = data.suffix(keptSize)
        let start = tail.firstIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? tail.startIndex
        return Data(tail[start...])
    }

    static func beforeLaunch() -> String {
        _ = handle
        guard let data = FileManager.default.contents(atPath: url.path) else { return "" }
        let offset = extent.withLock { $0.launchOffset }
        return String(decoding: data.prefix(Int(offset)), as: Unicode.UTF8.self)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func info(_ message: @autoclosure () -> String) { write(message()) }
    static func debug(_ message: @autoclosure () -> String) { if verbose { write(message()) } }

    static func attempt(_ action: String, _ body: () throws -> Void) {
        do { try body() } catch { info("\(action) failed: \(error)") }
    }

    private static func write(_ message: String) {
        let line = Data("\(time.string(from: Date())) \(message)\n".utf8)
        guard let handle else { return }
        extent.withLock { extent in
            if extent.size > UInt64(maxSize) { trim(handle, &extent) }
            try? handle.write(contentsOf: line)
            extent.size += UInt64(line.count)
        }
    }

    private static func trim(_ handle: FileHandle, _ extent: inout Extent) {
        guard let data = FileManager.default.contents(atPath: url.path) else { return }
        let kept = tail(of: data)
        try? handle.truncate(atOffset: 0)
        try? handle.write(contentsOf: kept)
        let removed = UInt64(data.count - kept.count)
        extent.launchOffset = extent.launchOffset > removed ? extent.launchOffset - removed : 0
        extent.size = UInt64(kept.count)
    }
}
