import AppKit

struct TemplateMatchStability {
    static let settleTime: TimeInterval = 0.6
    private var provisional: [UUID: (candidate: TemplateWindowCandidate, since: Date)] = [:]

    mutating func waiting(saved: [WorkspaceTemplate.SavedWindow], candidates: [TemplateWindowCandidate],
                          assigned: [UUID: CGWindowID], now: Date) -> Bool {
        let byID = Dictionary(candidates.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var next: [UUID: (candidate: TemplateWindowCandidate, since: Date)] = [:]
        for window in saved {
            guard let id = assigned[window.id], let candidate = byID[id],
                  let score = TemplateWindowMatch.score(window, title: candidate.title, document: candidate.document,
                                                        windowID: id, launchDate: candidate.launchDate),
                  score == 0 || (score == 1 && window.document != nil) else { continue }
            let old = provisional[window.id]
            let since = old.flatMap { $0.candidate == candidate ? $0.since : nil } ?? now
            next[window.id] = (candidate, since)
        }
        provisional = next
        return next.values.contains { now.timeIntervalSince($0.since) + 0.001 < Self.settleTime }
    }
}
