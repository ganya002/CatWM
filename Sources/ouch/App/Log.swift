// App: plain-text log at ~/Library/Logs/ouch.log.
import Foundation

/// Plain-text log at ~/Library/Logs/ouch.log. `debug` lines only appear when launched with `--verbose`
/// (or with the older `debug-logging = true` in the config file).
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ouch.log")
    static var verbose = false
    /// `open ouch.app --args --verbose`
    static let verboseLaunch = CommandLine.arguments.contains("--verbose")

    /// Where this run's lines start; everything before it is from earlier runs.
    private static var launchOffset: UInt64 = 0

    private static let handle: FileHandle? = {
        let fm = FileManager.default
        // A long log keeps its newest part, so a crash report still has the lines before the crash.
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000,
           let data = fm.contents(atPath: url.path) {
            try? data.suffix(500_000).write(to: url)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        launchOffset = (try? h?.seekToEnd()) ?? 0
        return h
    }()

    /// The log as it was when this run started: the last lines are the previous run's.
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
