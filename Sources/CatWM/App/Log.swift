import Foundation

enum Log {
    static let url = NSClassFromString("XCTestCase") == nil
        ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CatWM.log")
        : FileManager.default.temporaryDirectory.appendingPathComponent("CatWM-test-\(getpid()).log")
    static let verboseLaunch = LaunchFlag.verbose.isSet

    static let maxSize = 2_000_000
    static let keptSize = 500_000

    private final class File {
        let lock = NSLock()
        let handle: FileHandle?
        var launchOffset: UInt64
        var size: UInt64
        var verbose = false

        init() {
            let fileManager = FileManager.default
            if let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize,
               let data = fileManager.contents(atPath: url.path) {
                try? tail(of: data).write(to: url)
            }
            if !fileManager.fileExists(atPath: url.path) { fileManager.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url)
            launchOffset = (try? handle?.seekToEnd()) ?? 0
            size = launchOffset
        }
    }

    private static let file = File()

    static var verbose: Bool {
        get { file.lock.withLock { file.verbose } }
        set { file.lock.withLock { file.verbose = newValue } }
    }

    static func tail(of data: Data) -> Data {
        guard data.count > keptSize else { return data }
        let tail = data.suffix(keptSize)
        let start = tail.firstIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? tail.startIndex
        return Data(tail[start...])
    }

    static func beforeLaunch() -> String {
        let offset = file.lock.withLock { file.launchOffset }
        guard let data = FileManager.default.contents(atPath: url.path) else { return "" }
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
        guard let handle = file.handle else { return }
        file.lock.withLock {
            if file.size > UInt64(maxSize) { trim(handle) }
            try? handle.write(contentsOf: line)
            file.size += UInt64(line.count)
        }
    }

    private static func trim(_ handle: FileHandle) {
        guard let data = FileManager.default.contents(atPath: url.path) else { return }
        let kept = tail(of: data)
        try? handle.truncate(atOffset: 0)
        try? handle.write(contentsOf: kept)
        let removed = UInt64(data.count - kept.count)
        file.launchOffset = file.launchOffset > removed ? file.launchOffset - removed : 0
        file.size = UInt64(kept.count)
    }
}
