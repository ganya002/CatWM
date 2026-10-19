import Foundation

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ouch.log")
    static var verbose = false
    static let verboseLaunch = CommandLine.arguments.contains("--verbose")

    private static var launchOffset: UInt64 = 0

    private static let handle: FileHandle? = {
        let fileManager = FileManager.default
        if let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000,
           let data = fileManager.contents(atPath: url.path) {
            try? data.suffix(500_000).write(to: url)
        }
        if !fileManager.fileExists(atPath: url.path) { fileManager.createFile(atPath: url.path, contents: nil) }
        let fileHandle = try? FileHandle(forWritingTo: url)
        launchOffset = (try? fileHandle?.seekToEnd()) ?? 0
        return fileHandle
    }()

    static func beforeLaunch() -> String {
        _ = handle
        guard let data = FileManager.default.contents(atPath: url.path) else { return "" }
        return String(decoding: data.prefix(Int(launchOffset)), as: Unicode.UTF8.self)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func info(_ message: @autoclosure () -> String) { write(message()) }
    static func debug(_ message: @autoclosure () -> String) { if verbose { write(message()) } }

    private static func write(_ message: String) {
        try? handle?.write(contentsOf: Data("\(time.string(from: Date())) \(message)\n".utf8))
    }
}
