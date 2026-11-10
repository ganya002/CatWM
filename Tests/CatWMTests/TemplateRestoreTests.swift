import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

private let bundle = "com.example.editor"
private let launch = Date(timeIntervalSince1970: 100)

private func target(
    document: String? = nil,
    bundleID: String = bundle,
    app: String = "Editor"
) -> RestoreTarget {
    RestoreTarget(id: UUID(), bundleID: bundleID, appName: app, document: document)
}

private func savedWindow(title: String = "Draft", document: String? = nil, windowID: CGWindowID = 42,
                         launchDate: Date? = launch, bundleID: String = bundle) -> SavedWindow {
    SavedWindow(
        bundleID: bundleID, appName: "Editor", title: title, document: document, display: "main",
        frame: .zero, floating: false, minimized: false, fullscreen: false, zoomed: false,
        focused: false, windowID: windowID, launchDate: launchDate
    )
}

private func candidate(id: CGWindowID, title: String, document: String? = nil, launchDate: Date? = nil,
                       fallback: Bool, bundleID: String = bundle) -> WindowCandidate {
    WindowCandidate(windowID: id, bundleID: bundleID, title: title, document: document, launchDate: launchDate,
                            allowsGenericFallback: fallback)
}

private func warm(_ bundleID: String = bundle) -> [String: AppLaunchState] {
    [bundleID: AppLaunchState(running: true, finishedLaunching: true, openable: true)]
}

@Suite struct TemplateRestoreTests {
    @Test func moreThanTenWindowsAreAllRequestedInsideTheWait() {
        var scheduler = RestoreScheduler()
        let windows = (1...12).map { _ in target(document: "file:///tmp/\(UUID().uuidString).txt") }
        var now = Date(timeIntervalSince1970: 1_000)
        let deadline = now.addingTimeInterval(RestoreScheduler.totalWait)
        var requested: [UUID] = []
        while now < deadline {
            let step = scheduler.step(now: now, deadline: deadline, targets: windows, matched: [], apps: warm())
            let ids = step.requests.map(\.savedID)
            #expect(Set(ids).count == ids.count)
            requested.append(contentsOf: ids)
            if Set(requested).count == windows.count { break }
            now = now.addingTimeInterval(RestoreScheduler.pollInterval)
        }
        #expect(Set(requested) == Set(windows.map(\.id)))
        #expect(requested.count == windows.count)
        #expect(now.timeIntervalSince(Date(timeIntervalSince1970: 1_000)) < RestoreScheduler.totalWait)
    }

    @Test func aShortDeadlineStillRequestsEveryRemainingWindow() {
        var scheduler = RestoreScheduler()
        let windows = (1...12).map { _ in target() }
        let now = Date(timeIntervalSince1970: 1_000)
        let step = scheduler.step(
            now: now, deadline: now.addingTimeInterval(1), targets: windows, matched: [], apps: warm()
        )
        #expect(Set(step.requests.map(\.savedID)) == Set(windows.map(\.id)))
        let again = scheduler.step(
            now: now, deadline: now.addingTimeInterval(1), targets: windows, matched: [], apps: warm()
        )
        #expect(again.requests.isEmpty)
    }

    @Test func refusedAndFailedOpensRetryWhileAcceptedOpensStayPending() {
        var scheduler = RestoreScheduler()
        let accepted = target(document: "file:///tmp/accepted.txt")
        let refused = target(document: "file:///tmp/refused.txt")
        let failed = target(document: "file:///tmp/failed.txt")
        let windows = [accepted, refused, failed]
        var now = Date(timeIntervalSince1970: 2_000)
        let deadline = now.addingTimeInterval(RestoreScheduler.totalWait)
        var tokens: [UUID: UUID] = [:]
        for window in windows {
            let step = scheduler.step(now: now, deadline: deadline, targets: windows, matched: [], apps: warm())
            #expect(step.requests.map(\.savedID) == [window.id])
            tokens[window.id] = step.requests[0].token
            now = now.addingTimeInterval(RestoreScheduler.pollInterval)
        }
        let pending = scheduler.step(now: now, deadline: deadline, targets: windows, matched: [], apps: warm())
        #expect(pending.requests.isEmpty)
        #expect(pending.keepWaiting)
        scheduler.noteRefused(refused.id, appName: refused.appName, now: now)
        scheduler.noteFailed(failed.id, token: tokens[failed.id] ?? UUID(), appName: failed.appName, now: now)
        let tooSoon = scheduler.step(now: now, deadline: deadline, targets: windows, matched: [], apps: warm())
        #expect(tooSoon.requests.isEmpty)
        now = now.addingTimeInterval(RestoreScheduler.retryDelay)
        let firstRetry = scheduler.step(now: now, deadline: deadline, targets: windows, matched: [], apps: warm())
        #expect(firstRetry.requests.map(\.savedID) == [refused.id])
        now = now.addingTimeInterval(RestoreScheduler.pollInterval)
        let secondRetry = scheduler.step(now: now, deadline: deadline, targets: windows, matched: [], apps: warm())
        #expect(secondRetry.requests.map(\.savedID) == [failed.id])
        let stale = scheduler.step(now: now.addingTimeInterval(RestoreScheduler.retryDelay), deadline: deadline,
                                   targets: [accepted], matched: [], apps: warm())
        #expect(stale.requests.isEmpty)
        scheduler.noteFailed(failed.id, token: tokens[failed.id] ?? UUID(), appName: failed.appName,
                             now: now.addingTimeInterval(1))
        let kept = scheduler.step(now: now.addingTimeInterval(RestoreScheduler.retryDelay), deadline: deadline,
                                  targets: [failed], matched: [], apps: warm())
        #expect(kept.requests.isEmpty)
    }

    @Test func duplicateDocumentsAreRequestedOncePerSavedWindow() {
        var scheduler = RestoreScheduler()
        let first = target(document: "file:///tmp/draft.txt")
        let second = target(document: "file:///tmp/draft.txt")
        var now = Date(timeIntervalSince1970: 3_000)
        let deadline = now.addingTimeInterval(RestoreScheduler.totalWait)
        var requested: [UUID] = []
        while requested.count < 2, now < deadline {
            let step = scheduler.step(now: now, deadline: deadline, targets: [first, second], matched: [], apps: warm())
            requested.append(contentsOf: step.requests.map(\.savedID))
            now = now.addingTimeInterval(RestoreScheduler.pollInterval)
        }
        #expect(requested == [first.id, second.id])
        let extra = scheduler.step(now: now, deadline: deadline, targets: [first, second], matched: [], apps: warm())
        #expect(extra.requests.isEmpty)
    }

    @Test func restoreStopsWhenNoRequestCanProgress() {
        var scheduler = RestoreScheduler()
        let missing = target(bundleID: "com.example.missing", app: "Missing")
        let now = Date(timeIntervalSince1970: 4_000)
        let deadline = now.addingTimeInterval(RestoreScheduler.totalWait)
        let absent = AppLaunchState(running: false, finishedLaunching: false, openable: false)
        let stopped = scheduler.step(
            now: now, deadline: deadline, targets: [missing], matched: [], apps: [missing.bundleID: absent]
        )
        #expect(stopped.launch.isEmpty)
        #expect(stopped.requests.isEmpty)
        #expect(!stopped.keepWaiting)
        #expect(scheduler.failures.contains("Missing"))
        let matched = target()
        let done = scheduler.step(now: now, deadline: deadline, targets: [matched], matched: [matched.id], apps: warm())
        #expect(!done.keepWaiting)
        #expect(done.requests.isEmpty)
    }

    @Test func exhaustedRetriesStopBeforeTheDeadline() {
        var scheduler = RestoreScheduler()
        let window = target()
        var now = Date(timeIntervalSince1970: 5_000)
        let deadline = now.addingTimeInterval(RestoreScheduler.totalWait)
        for _ in 0..<RestoreScheduler.maxAttempts {
            let step = scheduler.step(now: now, deadline: deadline, targets: [window], matched: [], apps: warm())
            #expect(step.requests.map(\.savedID) == [window.id])
            scheduler.noteRefused(window.id, appName: window.appName, now: now)
            now = now.addingTimeInterval(RestoreScheduler.retryDelay)
        }
        let stopped = scheduler.step(now: now, deadline: deadline, targets: [window], matched: [], apps: warm())
        #expect(stopped.requests.isEmpty)
        #expect(!stopped.keepWaiting)
        #expect(now < deadline)
        #expect(scheduler.failures.contains(window.appName))
    }

    @Test func aFailedLaunchStopsWaiting() {
        var scheduler = RestoreScheduler()
        let window = target()
        let now = Date(timeIntervalSince1970: 6_000)
        let deadline = now.addingTimeInterval(RestoreScheduler.totalWait)
        let apps = [bundle: AppLaunchState(running: false, finishedLaunching: false, openable: true)]
        let launching = scheduler.step(now: now, deadline: deadline, targets: [window], matched: [], apps: apps)
        #expect(launching.launch == [bundle])
        #expect(launching.keepWaiting)
        scheduler.noteLaunchFailed(bundle, appName: window.appName)
        let stopped = scheduler.step(
            now: now.addingTimeInterval(0.2), deadline: deadline, targets: [window], matched: [], apps: apps
        )
        #expect(stopped.launch.isEmpty)
        #expect(stopped.requests.isEmpty)
        #expect(!stopped.keepWaiting)
    }
}

@Suite struct TemplateRestoreLaunchTests {
    @Test func coldLaunchSettlesBeforeSyntheticAndDocumentOpens() {
        var scheduler = RestoreScheduler()
        let created = target()
        let opened = target(document: "file:///tmp/draft.txt")
        var now = Date(timeIntervalSince1970: 7_000)
        let deadline = now.addingTimeInterval(RestoreScheduler.totalWait)
        var apps = [bundle: AppLaunchState(running: false, finishedLaunching: false, openable: true)]
        let launching = scheduler.step(
            now: now, deadline: deadline, targets: [created, opened], matched: [], apps: apps
        )
        #expect(launching.launch == [bundle])
        #expect(launching.requests.isEmpty)
        #expect(launching.keepWaiting)
        let repeatLaunch = scheduler.step(
            now: now, deadline: deadline, targets: [created, opened], matched: [], apps: apps
        )
        #expect(repeatLaunch.launch.isEmpty)
        #expect(repeatLaunch.keepWaiting)
        now = now.addingTimeInterval(1)
        apps[bundle] = AppLaunchState(running: true, finishedLaunching: false, openable: true)
        let starting = scheduler.step(now: now, deadline: deadline, targets: [created, opened], matched: [], apps: apps)
        #expect(starting.requests.isEmpty)
        #expect(starting.keepWaiting)
        now = now.addingTimeInterval(0.2)
        apps[bundle] = AppLaunchState(running: true, finishedLaunching: true, openable: true)
        let settling = scheduler.step(now: now, deadline: deadline, targets: [created, opened], matched: [], apps: apps)
        #expect(settling.requests.isEmpty)
        #expect(settling.keepWaiting)
        now = now.addingTimeInterval(RestoreScheduler.launchSettle)
        let ready = scheduler.step(now: now, deadline: deadline, targets: [created, opened], matched: [], apps: apps)
        #expect(ready.requests.map(\.savedID) == [created.id])
        #expect(ready.requests[0].document == nil)
        now = now.addingTimeInterval(RestoreScheduler.pollInterval)
        let document = scheduler.step(now: now, deadline: deadline, targets: [created, opened], matched: [], apps: apps)
        #expect(document.requests.map(\.savedID) == [opened.id])
        #expect(document.requests[0].document == opened.document)
    }

    @Test func aRunningAppIsRequestedImmediately() {
        var scheduler = RestoreScheduler()
        let window = target(document: "file:///tmp/draft.txt")
        let now = Date(timeIntervalSince1970: 8_000)
        let step = scheduler.step(now: now, deadline: now.addingTimeInterval(RestoreScheduler.totalWait),
                                  targets: [window], matched: [], apps: warm())
        #expect(step.launch.isEmpty)
        #expect(step.requests.map(\.savedID) == [window.id])
        #expect(step.keepWaiting)
    }

    @Test func aColdAppsDelayedFirstWindowPreventsAnExtraNewWindow() {
        var scheduler = RestoreScheduler()
        let window = target()
        let start = Date(timeIntervalSince1970: 25_000)
        let deadline = start.addingTimeInterval(RestoreScheduler.totalWait)
        let cold = [bundle: AppLaunchState(running: false, finishedLaunching: false, openable: true)]
        let coldStep = scheduler.step(now: start, deadline: deadline, targets: [window], matched: [], apps: cold)
        #expect(coldStep.launch == [bundle])
        #expect(scheduler.step(now: start.addingTimeInterval(0.3), deadline: deadline, targets: [window],
                               matched: [], apps: warm()).requests.isEmpty)
        #expect(scheduler.step(now: start.addingTimeInterval(1.5), deadline: deadline, targets: [window],
                               matched: [], apps: warm()).requests.isEmpty)
        let appeared = scheduler.step(now: start.addingTimeInterval(2), deadline: deadline, targets: [window],
                                       matched: [window.id], apps: warm())
        #expect(appeared.requests.isEmpty)
        #expect(!appeared.keepWaiting)
    }

    @Test func launchProgressDelaysOnlyTheInitialSyntheticRequest() {
        var scheduler = RestoreScheduler()
        let windows = [target(), target(), target(), target()]
        let start = Date(timeIntervalSince1970: 20_000)
        let deadline = start.addingTimeInterval(RestoreScheduler.totalWait)
        let cold = [bundle: AppLaunchState(running: false, finishedLaunching: false, openable: true)]
        let coldStep = scheduler.step(now: start, deadline: deadline, targets: windows, matched: [], apps: cold)
        #expect(coldStep.launch == [bundle])
        #expect(scheduler.step(now: start.addingTimeInterval(1), deadline: deadline, targets: windows,
                               matched: [], apps: warm()).requests.isEmpty)
        #expect(scheduler.step(now: start.addingTimeInterval(1.5), deadline: deadline, targets: windows,
                               matched: [windows[0].id], apps: warm()).requests.isEmpty)
        #expect(scheduler.step(now: start.addingTimeInterval(1.8), deadline: deadline, targets: windows,
                               matched: [windows[0].id], apps: warm()).requests.isEmpty)
        let ready = scheduler.step(now: start.addingTimeInterval(2.25), deadline: deadline, targets: windows,
                                   matched: [windows[0].id], apps: warm())
        #expect(ready.requests.map(\.savedID) == [windows[1].id])
        let next = scheduler.step(now: start.addingTimeInterval(2.55), deadline: deadline, targets: windows,
                                  matched: [windows[0].id, windows[1].id], apps: warm())
        #expect(next.requests.map(\.savedID) == [windows[2].id])
    }

    @Test func separateAppsAreRequestedInTheSamePass() {
        var scheduler = RestoreScheduler()
        let editor = target()
        let browser = target(bundleID: "com.example.browser", app: "Browser")
        var apps = warm()
        apps[browser.bundleID] = AppLaunchState(running: true, finishedLaunching: true, openable: true)
        let now = Date(timeIntervalSince1970: 9_000)
        let step = scheduler.step(now: now, deadline: now.addingTimeInterval(RestoreScheduler.totalWait),
                                  targets: [editor, browser], matched: [], apps: apps)
        #expect(Set(step.requests.map(\.savedID)) == [editor.id, browser.id])
    }

    @Test func cancellationStopsNewRequestsAndIgnoresLateErrors() {
        var scheduler = RestoreScheduler()
        let window = target(document: "file:///tmp/draft.txt")
        let now = Date(timeIntervalSince1970: 10_000)
        let deadline = now.addingTimeInterval(RestoreScheduler.totalWait)
        let started = scheduler.step(now: now, deadline: deadline, targets: [window], matched: [], apps: warm())
        let token = started.requests[0].token
        scheduler.cancel()
        let stopped = scheduler.step(
            now: now.addingTimeInterval(RestoreScheduler.retryDelay), deadline: deadline,
            targets: [window], matched: [], apps: warm()
        )
        #expect(stopped.requests.isEmpty)
        #expect(stopped.launch.isEmpty)
        #expect(!stopped.keepWaiting)
        scheduler.noteFailed(window.id, token: token, appName: window.appName, now: now.addingTimeInterval(2))
        scheduler.noteLaunchFailed(bundle, appName: window.appName)
        #expect(scheduler.failures.isEmpty)
        let later = scheduler.step(
            now: now.addingTimeInterval(3), deadline: deadline, targets: [window], matched: [], apps: warm()
        )
        #expect(later.requests.isEmpty)
    }
}

@Suite struct TemplateWindowMatchTests {
    @Test func aLaterStrongMatchReplacesAProvisionalWindow() {
        let notes = savedWindow(title: "Notes", document: nil, windowID: 1, launchDate: nil)
        let draft = savedWindow(title: "Draft", document: "file:///tmp/draft.txt", windowID: 42, launchDate: launch)
        let hidden = candidate(id: 42, title: "", fallback: true)
        let early = WindowMatch.assign([notes, draft], candidates: [hidden])
        #expect(early[notes.id] == 42)
        #expect(early[draft.id] == nil)
        let revealed = candidate(id: 42, title: "Draft", document: draft.document, launchDate: launch, fallback: true)
        let late = WindowMatch.assign([notes, draft], candidates: [revealed])
        #expect(late[draft.id] == 42)
        #expect(late[notes.id] == nil)
        let titled = candidate(id: 7, title: "Draft", fallback: true)
        #expect(WindowMatch.assign([draft], candidates: [titled])[draft.id] == 7)
        let exact = candidate(id: 42, title: "Renamed", document: draft.document, launchDate: launch, fallback: false)
        #expect(WindowMatch.assign([draft], candidates: [titled, exact])[draft.id] == 42)
    }

    @Test func genericFallbackSkipsUnrelatedTitlesAndOtherSpaces() {
        let saved = savedWindow(title: "Draft", document: nil, windowID: 42, launchDate: launch)
        let unrelated = candidate(id: 3, title: "Inbox", fallback: true)
        let otherSpace = candidate(id: 4, title: "", fallback: false)
        #expect(WindowMatch.score(saved, title: unrelated.title, document: nil, windowID: unrelated.windowID,
                                         launchDate: nil) == 0)
        #expect(WindowMatch.assign([saved], candidates: [unrelated, otherSpace]).isEmpty)
        let original = candidate(
            id: 9, title: "Draft", document: nil, launchDate: Date(timeIntervalSince1970: 200), fallback: false
        )
        #expect(WindowMatch.assign([saved], candidates: [unrelated, otherSpace, original])[saved.id] == 9)
        let untitled = candidate(id: 5, title: "", fallback: true)
        #expect(WindowMatch.assign([saved], candidates: [unrelated, otherSpace, untitled])[saved.id] == 5)
        let savedDocument = savedWindow(
            title: "Draft", document: "file:///tmp/draft.txt", windowID: 42, launchDate: launch
        )
        let elsewhere = candidate(id: 8, title: "Notes", document: savedDocument.document, fallback: false)
        #expect(WindowMatch.assign([savedDocument], candidates: [unrelated, elsewhere])[savedDocument.id] == 8)
    }

    @Test func oneDocumentWindowIsNotAssignedToTwoSavedWindows() {
        let first = savedWindow(document: "file:///tmp/draft.txt", windowID: 1)
        let second = savedWindow(document: "file:///tmp/draft.txt", windowID: 2)
        let window = candidate(id: 4, title: "Draft", document: "file:///tmp/draft.txt", fallback: false)
        let assigned = WindowMatch.assign([first, second], candidates: [window])
        #expect(assigned[first.id] == 4)
        #expect(assigned[second.id] == nil)
    }

    @Test func strongerCandidatesOutrankGenericFallback() {
        let plain = savedWindow(title: "Draft", document: nil, windowID: 42, launchDate: launch)
        let generic = candidate(id: 1, title: "", fallback: true)
        let title = candidate(id: 2, title: "Draft", fallback: true)
        #expect(WindowMatch.assign([plain], candidates: [generic, title])[plain.id] == 2)
        let saved = savedWindow(title: "Draft", document: "file:///tmp/draft.txt", windowID: 42, launchDate: launch)
        let titled = candidate(id: 2, title: "Draft", fallback: true)
        let document = candidate(id: 3, title: "Other", document: saved.document, fallback: true)
        let exact = candidate(id: 42, title: "Other", document: saved.document, launchDate: launch, fallback: false)
        #expect(WindowMatch.assign([saved], candidates: [titled, document])[saved.id] == 3)
        #expect(WindowMatch.assign([saved], candidates: [titled, document, exact])[saved.id] == 42)
    }

    @Test func aMissedScanKeepsThePreviousMatch() {
        let savedID = UUID()
        let missed = WindowMatch.retainUnscanned([savedID: 7], assigned: [:], scanned: [])
        #expect(missed[savedID] == 7)
        let replaced = WindowMatch.retainUnscanned([savedID: 7], assigned: [savedID: 42], scanned: [7, 42])
        #expect(replaced[savedID] == 42)
        let rejected = WindowMatch.retainUnscanned([savedID: 7], assigned: [:], scanned: [7])
        #expect(rejected.isEmpty)
    }

    @Test func genericFallbackStaysOnTheCurrentShownWorkspace() {
        #expect(!WindowMatch.allowsGenericFallback(offSpace: true, hiddenWorkspace: false))
        #expect(!WindowMatch.allowsGenericFallback(offSpace: false, hiddenWorkspace: true))
        #expect(WindowMatch.allowsGenericFallback(offSpace: false, hiddenWorkspace: false))
    }

    @Test func missingCommandModifiersAreNotTreatedAsCommandN() {
        #expect(!NewWindowCommand.isPlainCommandN(command: "n", modifiers: nil))
        #expect(!NewWindowCommand.isPlainCommandN(command: "N", modifiers: nil))
        #expect(NewWindowCommand.isPlainCommandN(command: "n", modifiers: 0))
        #expect(NewWindowCommand.isPlainCommandN(command: "N", modifiers: 0))
        #expect(!NewWindowCommand.isPlainCommandN(command: "n", modifiers: 1))
        #expect(!NewWindowCommand.isPlainCommandN(command: "t", modifiers: 0))
        #expect(!NewWindowCommand.isPlainCommandN(command: nil, modifiers: 0))
    }
}
