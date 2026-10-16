import Foundation

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ouch.log")
    static var verbose = false
    static let verboseLaunch = CommandLine.arguments.contains("--verbose")

    private static var launchOffset: UInt64 = 0

    private static let handle: FileHandle? = {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000,
           let data = fm.contents(atPath: url.path) {
            try? data.suffix(500_000).write(to: url)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        launchOffset = (try? h?.seekToEnd()) ?? 0
        return h
    }()

    static func beforeLaunch() -> String {
        _ = handle
        guard let data = FileManager.default.contents(atPath: url.path) else { return "" }
        return String(decoding: data.prefix(Int(launchOffset)), as: UTF8.self)
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ s: @autoclosure () -> String) { write(s()) }
    static func debug(_ s: @autoclosure () -> String) { if verbose { write(s()) } }

    private static func write(_ s: String) {
        try? handle?.write(contentsOf: Data("\(time.string(from: Date())) \(s)\n".utf8))
    }
}
