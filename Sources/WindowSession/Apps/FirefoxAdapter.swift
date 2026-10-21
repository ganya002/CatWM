import Compression
import CoreGraphics
import Darwin
import Foundation

struct FirefoxAdapter: AppAdapter {
    static let supportFolders: [String: String] = [
        "org.mozilla.firefox": "Firefox", "org.mozilla.firefoxdeveloperedition": "Firefox",
        "org.mozilla.nightly": "Firefox", "app.zen-browser.zen": "zen",
        "io.gitlab.librewolf-community": "LibreWolf", "one.ablaze.floorp": "Floorp",
        "net.waterfox.waterfox": "Waterfox"
    ]

    let bundleIDs = Set(FirefoxAdapter.supportFolders.keys)
    let captureNeedsAutomation = false
    let restoreNeedsAutomation = false

    func capture(bundleID: String, windows: [AppStateCapture.Window],
                 timeout _: TimeInterval) async -> [ScriptedWindow] {
        guard let folder = Self.supportFolders[bundleID] else { return [] }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(folder)/Profiles")
        return await Blocking.run(timeout: 3, fallback: []) {
            let files = Self.sessionFiles(in: root)
            return files.flatMap { file -> [ScriptedWindow] in
                guard let raw = try? Data(contentsOf: file), let json = MozLZ4.decode(raw) else { return [] }
                return Self.parse(json, windows: windows)
            }
        }
    }

    func restore(_ state: AppState, bundleID: String, appURL: URL, timeout _: TimeInterval) async -> Bool {
        let tabs = state.tabs.filter(BrowserScript.isOpenable)
        guard let first = tabs.first else { return false }
        let arguments = ["-new-window", first] + tabs.dropFirst().flatMap { ["-new-tab", $0] }
        return await AppLaunch.open(appURL, bundleID: bundleID, arguments: arguments)
    }

        static func sessionFiles(in root: URL) -> [URL] {
        let manager = FileManager.default
        let profiles = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let files = profiles.map { $0.appendingPathComponent("sessionstore-backups/recovery.jsonlz4") }
            .filter { manager.fileExists(atPath: $0.path) }
        let open = files.filter { file in
            isLocked(file.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".parentlock"))
        }
        if !open.isEmpty { return open }
        let dated = files.compactMap { file -> (URL, Date)? in
            let date = (try? manager.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
            return date.map { (file, $0) }
        }
        return dated.max { $0.1 < $1.1 }.map { [$0.0] } ?? []
    }

    static func isLocked(_ file: URL) -> Bool {
        let descriptor = open(file.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var probe = flock()
        probe.l_type = Int16(F_WRLCK)
        probe.l_whence = Int16(SEEK_SET)
        guard fcntl(descriptor, F_GETLK, &probe) == 0 else { return false }
        return probe.l_type != Int16(F_UNLCK)
    }

    static func parse(_ json: Data, windows: [AppStateCapture.Window]) -> [ScriptedWindow] {
        guard let session = try? JSONDecoder().decode(FirefoxSession.self, from: json) else { return [] }
        var used = Set<CGWindowID>()
        return session.windows.compactMap { entry in
            let tabs = entry.tabs.map(\.openURL)
            let selected = max(0, (entry.selected ?? 1) - 1)
            let title = entry.tabs.indices.contains(selected) ? entry.tabs[selected].title : ""
            var frame = entry.frame
            var name = entry.title ?? title
            let names = [entry.title, title].compactMap(\.self).filter { !$0.isEmpty }
            let owner = windows.first { window in
                !used.contains(window.id) && names.contains { window.title.hasPrefix($0) }
            }
            if let owner {
                used.insert(owner.id)
                name = owner.title
                frame = owner.frame
            }
            return ScriptedEntry(title: name, frame: frame.map { [$0.minX, $0.minY, $0.width, $0.height] },
                                 tabs: tabs, selected: selected).window()
        }
    }
}

private struct FirefoxSession: Decodable {
    var windows: [FirefoxWindow]
}

private struct FirefoxWindow: Decodable {
    var tabs: [FirefoxTab]
    var selected: Int?
    var title: String?
    var frame: CGRect?

    enum CodingKeys: String, CodingKey {
        case tabs, selected, title, screenX, screenY, width, height
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try values.decode([FirefoxTab].self, forKey: .tabs)
        selected = try values.decodeIfPresent(Int.self, forKey: .selected)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        func number(_ key: CodingKeys) -> Double? {
            if let value = try? values.decodeIfPresent(Double.self, forKey: key) { return value }
            return (try? values.decodeIfPresent(String.self, forKey: key)).flatMap { Double($0) }
        }
        if let x = number(.screenX), let y = number(.screenY),
           let width = number(.width), let height = number(.height) {
            frame = CGRect(x: x, y: y, width: width, height: height)
        }
    }
}

private struct FirefoxTab: Decodable {
    var entries: [FirefoxEntry]
    var index: Int?

    private var current: FirefoxEntry? {
        guard !entries.isEmpty else { return nil }
        return entries[min(max((index ?? entries.count) - 1, 0), entries.count - 1)]
    }

    var title: String { current?.title ?? "" }

    var openURL: String {
        guard let url = current?.url, let scheme = URL(string: url)?.scheme?.lowercased(),
              ["http", "https", "file", "ftp"].contains(scheme) else { return "" }
        return url
    }
}

private struct FirefoxEntry: Decodable {
    var url: String?
    var title: String?
}

enum MozLZ4 {
    static let magic = Array("mozLz40\0".utf8)

    static func decode(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 12, Array(bytes[0..<8]) == magic else { return nil }
        let size = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24
        guard size > 0, size < 256_000_000 else { return nil }
        var output = [UInt8](repeating: 0, count: size)
        let payload = Array(bytes[12...])
        let written = compression_decode_buffer(&output, size, payload, payload.count, nil, COMPRESSION_LZ4_RAW)
        return written == size ? Data(output) : nil
    }

    static func encode(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var output = [UInt8](repeating: 0, count: bytes.count + bytes.count / 255 + 64)
        let written = compression_encode_buffer(&output, output.count, bytes, bytes.count, nil, COMPRESSION_LZ4_RAW)
        guard written > 0 else { return nil }
        let size = bytes.count
        let length = (0..<4).map { UInt8(size >> ($0 * 8) & 255) }
        let header = magic + length
        return Data(header + output[0..<written])
    }
}
