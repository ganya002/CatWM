// App: plain-text log at ~/Library/Logs/ouch.log.
import Foundation

/// Plain-text log at ~/Library/Logs/ouch.log. `debug` lines only appear when launched with `--verbose`
/// (or with the older `debug-logging = true` in the config file).
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ouch.log")
    static var verbose = false
    /// `open ouch.app --args --verbose`
    static let verboseLaunch = CommandLine.arguments.contains("--verbose")

    private static let handle: FileHandle? = {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000 {
            try? fm.removeItem(at: url)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()

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
