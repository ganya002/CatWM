import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct TemplateMatchStabilityTests {
    @Test func missingDocumentMetadataGetsTimeToSettle() {
        let saved = WorkspaceTemplateTests().template().windows[0]
        let candidate = WindowCandidate(
            windowID: saved.windowID + 1, bundleID: saved.bundleID, title: saved.title,
            document: nil, launchDate: nil, allowsGenericFallback: true
        )
        let assigned = [saved.id: candidate.windowID]
        let start = Date()
        var stability = MatchStability()
        let waiting1 = stability.waiting(saved: [saved], candidates: [candidate], assigned: assigned, now: start)
        #expect(waiting1)
        let waiting2 = stability.waiting(
            saved: [saved], candidates: [candidate], assigned: assigned, now: start.addingTimeInterval(0.3)
        )
        #expect(waiting2)
        let waiting3 = !stability.waiting(saved: [saved], candidates: [candidate], assigned: assigned,
                                  now: start.addingTimeInterval(MatchStability.settleTime))
        #expect(waiting3)
    }

    @Test func aStrongDocumentMatchFinishesWithoutTheRemainingDelay() {
        let saved = WorkspaceTemplateTests().template().windows[0]
        var candidate = WindowCandidate(
            windowID: saved.windowID + 1, bundleID: saved.bundleID, title: saved.title,
            document: nil, launchDate: nil, allowsGenericFallback: true
        )
        let start = Date()
        var stability = MatchStability()
        let waiting4 = stability.waiting(
            saved: [saved], candidates: [candidate], assigned: [saved.id: candidate.windowID], now: start
        )
        #expect(waiting4)
        candidate.document = saved.document
        let waiting5 = !stability.waiting(
            saved: [saved], candidates: [candidate], assigned: [saved.id: candidate.windowID],
            now: start.addingTimeInterval(0.1)
        )
        #expect(waiting5)
    }

    @Test func aChangingProvisionalWindowRestartsItsSettlePeriod() {
        var saved = WorkspaceTemplateTests().template().windows[0]
        saved.document = nil
        let first = WindowCandidate(windowID: 1, bundleID: saved.bundleID, title: "", document: nil,
                                             launchDate: nil, allowsGenericFallback: true)
        let second = WindowCandidate(windowID: 2, bundleID: saved.bundleID, title: "", document: nil,
                                              launchDate: nil, allowsGenericFallback: true)
        let start = Date()
        var stability = MatchStability()
        let waiting6 = stability.waiting(
            saved: [saved], candidates: [first], assigned: [saved.id: first.windowID], now: start
        )
        #expect(waiting6)
        let waiting7 = stability.waiting(saved: [saved], candidates: [second], assigned: [saved.id: second.windowID],
                                 now: start.addingTimeInterval(0.5))
        #expect(waiting7)
        let waiting8 = stability.waiting(saved: [saved], candidates: [second], assigned: [saved.id: second.windowID],
                                 now: start.addingTimeInterval(0.7))
        #expect(waiting8)
        let waiting9 = !stability.waiting(saved: [saved], candidates: [second], assigned: [saved.id: second.windowID],
                                  now: start.addingTimeInterval(1.1))
        #expect(waiting9)
    }

    @Test func aDestroyedWindowIsNotRetainedAsAMissedScan() {
        let saved = UUID()
        #expect(WindowMatch.retainUnscanned([saved: 42], assigned: [:], scanned: []).count == 1)
        #expect(WindowMatch.retainUnscanned([saved: 42], assigned: [:], scanned: [], invalidated: [42]).isEmpty)
    }

    @Test func aReopenedWindowCanHaveANewTitleWithoutReusingAnUnrelatedOldWindow() {
        var saved = WorkspaceTemplateTests().template().windows[0]
        saved.document = nil
        var candidate = WindowCandidate(windowID: saved.windowID + 1, bundleID: saved.bundleID,
                                                 title: "New session", document: nil, launchDate: nil,
                                                 allowsGenericFallback: true)
        #expect(WindowMatch.assign([saved], candidates: [candidate]).isEmpty)
        candidate.newlyOpened = true
        #expect(WindowMatch.assign([saved], candidates: [candidate])[saved.id] == candidate.windowID)
        candidate.allowsGenericFallback = false
        #expect(WindowMatch.assign([saved], candidates: [candidate]).isEmpty)
    }
}

@Suite struct TemplateMatchStabilityCapTests {
    @Test func aWindowWhoseTitleKeepsChangingStopsWaitingAtTheMaximum() {
        var saved = WorkspaceTemplateTests().template().windows[0]
        saved.document = nil
        let start = Date()
        var stability = MatchStability()
        var waiting = true
        for step in 0...12 {
            let candidate = WindowCandidate(windowID: 1, bundleID: saved.bundleID, title: "title \(step)",
                                                    document: nil, launchDate: nil, allowsGenericFallback: true)
            waiting = stability.waiting(saved: [saved], candidates: [candidate], assigned: [saved.id: 1],
                                        now: start.addingTimeInterval(Double(step) * 0.2))
            if step == 5 { #expect(waiting) }
        }
        #expect(!waiting)
    }
}
