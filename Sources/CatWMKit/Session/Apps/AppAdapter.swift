import AppKit

package struct ScriptedWindow: Equatable, Sendable {
    package var title: String
    package var frame: CGRect?
    package var state: AppState
}

package protocol AppAdapter: Sendable {
    var bundleIDs: Set<String> { get }
    var captureNeedsAutomation: Bool { get }
    var restoreNeedsAutomation: Bool { get }
    func capture(bundleID: String, windows: [AppStateCapture.Window], timeout: TimeInterval) async -> [ScriptedWindow]
    func restore(_ state: AppState, bundleID: String, appURL: URL, timeout: TimeInterval) async -> Bool
}

package enum AppAdapters {
    package static let all: [any AppAdapter] = [SafariAdapter(), ChromiumAdapter(), TerminalAdapter(),
                                                ITermAdapter(), FinderAdapter(), CodeEditorAdapter(),
                                                ZedAdapter(), XcodeAdapter()]

    package static func adapter(for bundleID: String) -> (any AppAdapter)? {
        all.first { $0.bundleIDs.contains(bundleID) }
    }

    package static func canRestore(_ state: AppState, bundleID: String) async -> Bool {
        guard !state.tabs.isEmpty, let adapter = adapter(for: bundleID) else { return false }
        guard adapter.restoreNeedsAutomation else { return true }
        return await Automation.access(bundleID, ask: false, timeout: 1) == .granted
    }

    package static func restore(_ state: AppState, bundleID: String, appURL: URL) async -> Bool {
        guard let adapter = adapter(for: bundleID) else { return false }
        return await adapter.restore(state, bundleID: bundleID, appURL: appURL, timeout: 4)
    }
}

package enum AppStateCapture {
    package struct Window: Sendable {
        package var id: CGWindowID
        package var bundleID: String
        package var title: String
        package var frame: CGRect
        package var document: String?

        package init(id: CGWindowID, bundleID: String, title: String, frame: CGRect, document: String? = nil) {
            self.id = id
            self.bundleID = bundleID
            self.title = title
            self.frame = frame
            self.document = document
        }
    }

    package static func capture(_ windows: [Window], consentWait: TimeInterval,
                                scriptTimeout: TimeInterval) async -> [CGWindowID: AppState] {
        let bundles = Set(windows.map(\.bundleID)).filter { AppAdapters.adapter(for: $0) != nil }.sorted()
        return await withTaskGroup(of: [CGWindowID: AppState].self) { group in
            for bundle in bundles {
                guard let adapter = AppAdapters.adapter(for: bundle) else { continue }
                let owned = windows.filter { $0.bundleID == bundle }
                group.addTask {
                    if adapter.captureNeedsAutomation,
                       await Automation.access(bundle, ask: true, timeout: consentWait) != .granted {
                        return [:]
                    }
                    let scripted = await adapter.capture(bundleID: bundle, windows: owned, timeout: scriptTimeout)
                    return attach(scripted, to: owned)
                }
            }
            var result: [CGWindowID: AppState] = [:]
            for await found in group { result.merge(found) { first, _ in first } }
            return result
        }
    }

    package static func attach(_ scripted: [ScriptedWindow], to windows: [Window]) -> [CGWindowID: AppState] {
        var pairs: [Pair] = []
        for window in windows {
            for (index, entry) in scripted.enumerated() {
                guard let cost = cost(entry, window) else { continue }
                pairs.append(Pair(window: window, index: index, cost: cost))
            }
        }
        pairs.sort { $0.cost == $1.cost ? $0.window.id < $1.window.id : $0.cost < $1.cost }
        var used = Set<Int>()
        var result: [CGWindowID: AppState] = [:]
        for pair in pairs where result[pair.window.id] == nil && !used.contains(pair.index) {
            result[pair.window.id] = scripted[pair.index].state
            used.insert(pair.index)
        }
        return result
    }

    private struct Pair {
        package var window: Window
        package var index: Int
        package var cost: CGFloat
    }

    private static func cost(_ entry: ScriptedWindow, _ window: Window) -> CGFloat? {
        let titled = !entry.title.isEmpty && entry.title == window.title
        guard let frame = entry.frame else { return titled ? 1000 : nil }
        let distance = abs(frame.minX - window.frame.minX) + abs(frame.minY - window.frame.minY)
            + abs(frame.width - window.frame.width) + abs(frame.height - window.frame.height)
        guard distance.isFinite else { return titled ? 1000 : nil }
        if titled { return distance }
        return distance <= 24 ? distance + 500 : nil
    }
}

package struct ScriptedEntry: Decodable {
    package var title: String?
    package var frame: [Double]?
    package var tabs: [String]
    package var selected: Int?

    package static func decode(_ output: String?) -> [ScriptedEntry] {
        guard let data = output?.data(using: .utf8),
              let entries = try? JSONDecoder().decode([ScriptedEntry?].self, from: data) else { return [] }
        return entries.compactMap(\.self)
    }

    package func window(tabs mapped: [String]? = nil) -> ScriptedWindow? {
        let kept = (mapped ?? tabs).enumerated().filter { !$0.element.isEmpty }
        let list = kept.map(\.element)
        guard !list.isEmpty else { return nil }
        let position = kept.firstIndex { $0.offset == selected ?? 0 } ?? 0
        let rect = frame.flatMap { values -> CGRect? in
            guard values.count == 4, values.allSatisfy(\.isFinite) else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        return ScriptedWindow(title: title ?? "", frame: rect,
                              state: AppState(tabs: list, selected: position))
    }
}

package enum ScriptText {
    package static let frameHelper = """
    function frameOf(b) {
      if (Array.isArray(b)) return [b[0], b[1], b[2] - b[0], b[3] - b[1]];
      return [b.x, b.y, b.width, b.height];
    }
    function safe(f, fallback) { try { return f(); } catch (e) { return fallback; } }
    """
}
