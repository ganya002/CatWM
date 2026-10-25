import AppKit
import SwiftUI

struct CrashSummary {
    let exception: String
    let frame: String?
    let date: Date

    var headline: String { [exception, frame].compactMap(\.self).joined(separator: " in ") }
    var time: String { DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short) }

    init?(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let newline = text.firstIndex(of: "\n"),
              let body = try? JSONSerialization.jsonObject(with: Data(text[newline...].utf8)) as? [String: Any]
        else { return nil }
        let exc = body["exception"] as? [String: Any]
        let type = exc?["type"] as? String ?? "Crash"
        exception = (exc?["signal"] as? String).map { "\(type) (\($0))" } ?? type
        let images = body["usedImages"] as? [[String: Any]] ?? []
        let threads = body["threads"] as? [[String: Any]] ?? []
        let faulting = body["faultingThread"] as? Int ?? 0
        let frames = faulting < threads.count ? threads[faulting]["frames"] as? [[String: Any]] ?? [] : []
        let ours = frames.first { frame in
            let i = frame["imageIndex"] as? Int ?? -1
            return i >= 0 && i < images.count && images[i]["name"] as? String == "CatWM"
        }
        frame = (ours ?? frames.first)?["symbol"] as? String
        date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }
}
