import CoreGraphics
import Foundation

struct WindowCandidate: Equatable {
    var windowID: CGWindowID
    var bundleID: String
    var title: String
    var document: String?
    var launchDate: Date?
    var allowsGenericFallback: Bool
    var newlyOpened = false
    var frame: CGRect?

    init(windowID: CGWindowID, bundleID: String, title: String, document: String?, launchDate: Date?,
         allowsGenericFallback: Bool, newlyOpened: Bool = false, frame: CGRect? = nil) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.title = title
        self.document = document
        self.launchDate = launchDate
        self.allowsGenericFallback = allowsGenericFallback
        self.newlyOpened = newlyOpened
        self.frame = frame
    }
}

enum WindowMatch {
    static func score(_ saved: SavedWindow, title: String, document: String?,
                      windowID: CGWindowID, launchDate: Date?) -> Int? {
        if let expected = saved.document, expected != document {
            guard document == nil, !saved.title.isEmpty, saved.title == title else {
                return saved.state == nil ? nil : 0
            }
        }
        if saved.windowID == windowID, let date = saved.launchDate, date == launchDate { return 3 }
        if saved.document != nil, saved.document == document { return 2 }
        if !saved.title.isEmpty, saved.title == title { return 1 }
        return saved.document == nil ? 0 : nil
    }

    static func allowsGenericFallback(offSpace: Bool, hiddenWorkspace: Bool) -> Bool {
        !offSpace && !hiddenWorkspace
    }

    static func assign(_ saved: [SavedWindow], candidates: [WindowCandidate]) -> [UUID: CGWindowID] {
        let rank = Dictionary(saved.enumerated().sorted { lhs, rhs in
            lhs.element.windowID == rhs.element.windowID ? lhs.offset < rhs.offset
                : lhs.element.windowID < rhs.element.windowID
        }.enumerated().map { ($0.element.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var used = Set<CGWindowID>()
        var result: [UUID: CGWindowID] = [:]
        for score in stride(from: 3, through: 0, by: -1) {
            var pairs: [Pair] = []
            for window in saved where result[window.id] == nil {
                for candidate in candidates where !used.contains(candidate.windowID)
                    && fits(candidate, window, score: score) {
                    pairs.append(Pair(window: window, candidate: candidate,
                                      distance: distance(window.frame, candidate.frame)))
                }
            }
            pairs.sort { lhs, rhs in
                if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
                let left = rank[lhs.window.id] ?? 0, right = rank[rhs.window.id] ?? 0
                return left == right ? lhs.candidate.windowID < rhs.candidate.windowID : left < right
            }
            for pair in pairs where result[pair.window.id] == nil && !used.contains(pair.candidate.windowID) {
                result[pair.window.id] = pair.candidate.windowID
                used.insert(pair.candidate.windowID)
            }
        }
        return result
    }

    static func retainUnscanned(_ previous: [UUID: CGWindowID], assigned: [UUID: CGWindowID],
                                scanned: Set<CGWindowID>,
                                invalidated: Set<CGWindowID> = []) -> [UUID: CGWindowID] {
        var next = assigned
        for (savedID, windowID) in previous
        where next[savedID] == nil && !scanned.contains(windowID) && !invalidated.contains(windowID) {
            next[savedID] = windowID
        }
        return next
    }

    private struct Pair {
        var window: SavedWindow
        var candidate: WindowCandidate
        var distance: CGFloat
    }

    private static func fits(_ candidate: WindowCandidate, _ window: SavedWindow, score: Int) -> Bool {
        guard candidate.bundleID == window.bundleID else { return false }
        let candidateScore = Self.score(window, title: candidate.title, document: candidate.document,
                                        windowID: candidate.windowID, launchDate: candidate.launchDate)
        guard candidateScore == score else { return false }
        if score == 0 {
            guard candidate.allowsGenericFallback else { return false }
            if !candidate.newlyOpened, let expected = window.document, let actual = candidate.document,
               expected != actual { return false }
            if !candidate.newlyOpened, !candidate.title.isEmpty, candidate.title != window.title { return false }
        }
        return true
    }

    private static func distance(_ saved: CGRect, _ found: CGRect?) -> CGFloat {
        guard let found, !found.isNull, !saved.isNull else { return .greatestFiniteMagnitude }
        let value = abs(saved.midX - found.midX) + abs(saved.midY - found.midY)
            + abs(saved.width - found.width) + abs(saved.height - found.height)
        return value.isFinite ? value : .greatestFiniteMagnitude
    }
}

struct MatchStability {
    static let settleTime: TimeInterval = 0.6
    static let maximumWait: TimeInterval = 2
    private struct Sighting {
        var candidate: WindowCandidate
        var since: Date
        var first: Date
    }

    private var provisional: [UUID: Sighting] = [:]

    init() {}

    mutating func waiting(saved: [SavedWindow], candidates: [WindowCandidate],
                          assigned: [UUID: CGWindowID], now: Date) -> Bool {
        let byID = Dictionary(candidates.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var next: [UUID: Sighting] = [:]
        for window in saved {
            guard let id = assigned[window.id], var candidate = byID[id],
                  let score = WindowMatch.score(window, title: candidate.title, document: candidate.document,
                                                windowID: id, launchDate: candidate.launchDate),
                  score == 0 || (score == 1 && window.document != nil) else { continue }
            candidate.frame = nil
            let old = provisional[window.id]
            let since = old.flatMap { $0.candidate == candidate ? $0.since : nil } ?? now
            next[window.id] = Sighting(candidate: candidate, since: since, first: old?.first ?? now)
        }
        provisional = next
        return next.values.contains {
            now.timeIntervalSince($0.since) + 0.001 < Self.settleTime
                && now.timeIntervalSince($0.first) + 0.001 < Self.maximumWait
        }
    }
}
