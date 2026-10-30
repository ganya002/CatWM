import AppKit

enum LaunchTarget: Equatable, Sendable {
    case app(URL)
    case open(URL)
}

struct LaunchRequest: Equatable, Sendable {
    var target: String
    var workspace: String?
    var display: String?
    var frame: CGRect?

    init?(_ text: String) {
        var rest = Self.trimmed(Substring(text))
        while let space = rest.lastIndex(where: \.isWhitespace), case let last = rest[rest.index(after: space)...],
              let equals = last.firstIndex(of: "="), Self.keys.contains(last[..<equals].lowercased()) {
            let value = String(last[last.index(after: equals)...])
            guard !value.isEmpty else { return nil }
            switch last[..<equals].lowercased() {
            case "workspace": workspace = value
            case "display": display = value
            default:
                guard let rect = Self.unitRect(value) else { return nil }
                frame = rect
            }
            rest = Self.trimmed(rest[..<space])
        }
        target = String(rest)
        guard !target.isEmpty else { return nil }
    }

    static let keys: Set<String> = ["workspace", "display", "frame"]

    private static func trimmed(_ text: Substring) -> Substring {
        guard let start = text.firstIndex(where: { !$0.isWhitespace }),
              let end = text.lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return text[start...end]
    }

    var placesWindow: Bool { workspace != nil || display != nil || frame != nil }

    static func unitRect(_ text: String) -> CGRect? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map { part -> Double? in
            let raw = part.trimmingCharacters(in: .whitespaces)
            if raw.hasSuffix("%") { return Double(raw.dropLast()).map { $0 / 100 } }
            return Double(raw)
        }
        guard parts.count == 4, let x = parts[0], let y = parts[1], let width = parts[2], let height = parts[3],
              x >= 0, y >= 0, width > 0, height > 0, x + width <= 1.0001, y + height <= 1.0001 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

enum Launcher {
    static let appFolders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                             "/System/Applications/Utilities", NSHomeDirectory() + "/Applications",
                             "/System/Library/CoreServices", "/System/Library/CoreServices/Applications"]

    static func resolve(_ text: String) -> LaunchTarget? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return .open(url)
        }
        let expanded = trimmed == "~" || trimmed.hasPrefix("~/") ? NSHomeDirectory() + trimmed.dropFirst() : trimmed
        if expanded.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: expanded) else { return nil }
            let url = URL(fileURLWithPath: expanded)
            return url.pathExtension == "app" ? .app(url) : .open(url)
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) { return .app(app) }
        let name = trimmed.hasSuffix(".app") ? trimmed : trimmed + ".app"
        for folder in appFolders {
            let path = folder + "/" + name
            if FileManager.default.fileExists(atPath: path) { return .app(URL(fileURLWithPath: path)) }
        }
        return nil
    }

    static func appURL(for target: LaunchTarget) -> URL? {
        switch target {
        case .app(let url): url
        case .open(let url): NSWorkspace.shared.urlForApplication(toOpen: url)
        }
    }

    static func bundleID(for target: LaunchTarget) -> String? {
        appURL(for: target).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    @discardableResult
    static func open(_ target: LaunchTarget, activates: Bool = true) async -> Bool {
        switch target {
        case .app(let url): return await launch(url, activates: activates)
        case .open(let url):
            guard let app = appURL(for: target) else { return false }
            return await open(url, withApp: app, activates: activates)
        }
    }

    static func open(_ url: URL, withApp appURL: URL, activates: Bool = false) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    static func launch(_ appURL: URL, arguments: [String] = [], activates: Bool = false) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        configuration.arguments = arguments
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    static func run(command: String) -> Bool {
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
