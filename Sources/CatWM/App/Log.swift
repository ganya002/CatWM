import Foundation

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CatWM.log")
    static var verbose = false
    static let verboseLaunch = CommandLine.arguments.contains("--verbose")

    static let maxSize = 2_000_000
    static let keptSize = 500_000

    private static var launchOffset: UInt64 = 0
    private static var size: UInt64 = 0
    private static let lock = NSLock()

    private static let handle: FileHandle? = {
        let fileManager = FileManager.default
        if let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize,
           let data = fileManager.contents(atPath: url.path) {
            try? tail(of: data).write(to: url)
        }
        if !fileManager.fileExists(atPath: url.path) { fileManager.createFile(atPath: url.path, contents: nil) }
        let fileHandle = try? FileHandle(forWritingTo: url)
        launchOffset = (try? fileHandle?.seekToEnd()) ?? 0
        size = launchOffset
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
        let offset = lock.withLock { launchOffset }
        return String(decoding: data.prefix(Int(offset)), as: Unicode.UTF8.self)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func info(_ message: @autoclosure () -> String) { write(message()) }
    static func debug(_ message: @autoclosure () -> String) { if verbose { write(message()) } }

    private static func write(_ message: String) {
        let line = Data("\(time.string(from: Date())) \(message)\n".utf8)
        guard let handle else { return }
        lock.withLock {
            if size > UInt64(maxSize) { trim(handle) }
            try? handle.write(contentsOf: line)
            size += UInt64(line.count)
        }
    }

    private static func trim(_ handle: FileHandle) {
        guard let data = FileManager.default.contents(atPath: url.path) else { return }
        let kept = tail(of: data)
        try? handle.truncate(atOffset: 0)
        try? handle.write(contentsOf: kept)
        let removed = UInt64(data.count - kept.count)
        launchOffset = launchOffset > removed ? launchOffset - removed : 0
        size = UInt64(kept.count)
    }
}
