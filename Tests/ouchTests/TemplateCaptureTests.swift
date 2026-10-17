import AppKit
import Testing
@testable import ouch

@Suite struct TemplateCaptureTests {
    @Test func minimizedWindowsCanReportADialogSubrole() {
        #expect(TemplateWindowKind.includes(subrole: kAXStandardWindowSubrole, minimized: false))
        #expect(TemplateWindowKind.includes(subrole: kAXStandardWindowSubrole, minimized: true))
        #expect(TemplateWindowKind.includes(subrole: kAXDialogSubrole, minimized: true))
        #expect(!TemplateWindowKind.includes(subrole: kAXDialogSubrole, minimized: false))
        #expect(!TemplateWindowKind.includes(subrole: "AXSheet", minimized: true))
        #expect(!TemplateWindowKind.includes(subrole: nil, minimized: true))
    }

    @Test func timeoutReturnsBeforeACaptureThatIgnoresCancellation() async {
        let slot = TemplateCaptureSlot<Int>()
        let pause = Pause()
        let calls = Counter()
        defer { pause.release() }
        let clock = ContinuousClock()
        let started = clock.now
        let outcome = await slot.run(within: .milliseconds(80)) {
            calls.bump()
            await pause.wait()
            return 1
        }
        #expect(outcome == .timedOut)
        #expect(clock.now - started < .seconds(2))
        #expect(calls.value == 1)
        pause.release()
        let deadline = Date().addingTimeInterval(2)
        while !slot.isIdle, Date() < deadline { await Task.yield() }
        #expect(slot.isIdle)
        let next = await slot.run(within: .seconds(1)) {
            calls.bump()
            return 2
        }
        #expect(next == .finished(2))
        #expect(calls.value == 2)
    }

    @Test func cancellationReturnsWhileTheCaptureKeepsRunning() async {
        let slot = TemplateCaptureSlot<Int>()
        let pause = Pause()
        let entered = Flag()
        defer { pause.release() }
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
            await slot.run(within: .seconds(30)) {
                entered.value = true
                await pause.wait()
                return 1
            }
        }
        let deadline = Date().addingTimeInterval(2)
        while !entered.value, Date() < deadline { await Task.yield() }
        task.cancel()
        let outcome = await task.value
        #expect(outcome == .cancelled)
        #expect(clock.now - started < .seconds(2))
        #expect(await slot.run(within: .milliseconds(50)) { 9 } == .busy)
    }

    @Test func occupiedSlotDoesNotReuseTheEarlierCapture() async {
        let slot = TemplateCaptureSlot<Int>()
        let pause = Pause()
        let calls = Counter()
        defer { pause.release() }
        let first = Task {
            await slot.run(within: .seconds(2)) {
                calls.bump()
                await pause.wait()
                return 1
            }
        }
        let deadline = Date().addingTimeInterval(2)
        while calls.value < 1, Date() < deadline { await Task.yield() }
        let second = await slot.run(within: .seconds(2)) {
            calls.bump()
            await pause.wait()
            return 2
        }
        #expect(second == .busy)
        #expect(calls.value == 1)
        pause.release()
        #expect(await first.value == .finished(1))
        let idleDeadline = Date().addingTimeInterval(2)
        while !slot.isIdle, Date() < idleDeadline { await Task.yield() }
        let third = await slot.run(within: .seconds(1)) {
            calls.bump()
            return 3
        }
        #expect(third == .finished(3))
        #expect(calls.value == 2)
    }

    @Test func lateCompletionDoesNotReplaceTheTimedOutResult() async {
        let slot = TemplateCaptureSlot<Int>()
        let pause = Pause()
        defer { pause.release() }
        let outcome = await slot.run(within: .milliseconds(40)) {
            await pause.wait()
            return 5
        }
        #expect(outcome == .timedOut)
        pause.release()
        let deadline = Date().addingTimeInterval(2)
        while !slot.isIdle, Date() < deadline { await Task.yield() }
        #expect(await slot.run(within: .seconds(1)) { 6 } == .finished(6))
    }

    @Test func stalledEnumerationIsNotACompleteTemplate() throws {
        let first = app(pid: 1)
        let second = app(pid: 2)
        var reads: [pid_t] = []
        let batch = TemplateWindowWalk.collect(apps: [first, second], budget: 5, stop: { false }) { app in
            reads.append(app.pid)
            return app.pid == first.pid ? .stalled : .windows([observed(id: 2)])
        }
        #expect(reads == [first.pid])
        #expect(!batch.complete)
        #expect(throws: WindowManager.TemplateError.incomplete) {
            try TemplateCaptureAssembler.make(facts: facts(), batch: batch)
        }
    }

    @Test func deadlineAndCancellationStopTheWalkBeforeLaterApps() {
        let apps = [app(pid: 1), app(pid: 2)]
        var expiredReads: [pid_t] = []
        let expired = TemplateWindowWalk.collect(apps: apps, budget: 0, stop: { false }) { app in
            expiredReads.append(app.pid)
            return .windows([observed(id: CGWindowID(app.pid))])
        }
        #expect(expiredReads.isEmpty)
        #expect(!expired.complete)
        var stoppedReads: [pid_t] = []
        let stopped = TemplateWindowWalk.collect(apps: apps, budget: 5, stop: { true }) { app in
            stoppedReads.append(app.pid)
            return .windows([observed(id: CGWindowID(app.pid))])
        }
        #expect(stoppedReads.isEmpty)
        #expect(!stopped.complete)
    }

    @Test func completeWalkKeepsEveryAppThatResponds() {
        let frozen = Date(timeIntervalSince1970: 10)
        let batch = TemplateWindowWalk.collect(apps: [app(pid: 4), app(pid: 9)], budget: 5, now: { frozen }, stop: { false }) { app in
            .windows([observed(id: CGWindowID(app.pid), title: app.name)])
        }
        #expect(batch.complete)
        #expect(batch.windows.map(\.windowID) == [4, 9])
    }

    @Test func savedWindowsKeepOrderMinimizedFullscreenAndLayout() throws {
        var savedFacts = facts(order: [7, 3])
        savedFacts.zoomed = ["desk": 3]
        savedFacts.fallbackFocus = 7
        let minimized = observed(id: 3, title: "Draft", minimized: true)
        let fullscreen = observed(id: 7, title: "Talk", fullscreen: true)
        let template = try TemplateCaptureAssembler.make(facts: savedFacts, batch: .init(windows: [minimized, fullscreen], focusedID: nil, complete: true))
        #expect(template.tilingEnabled)
        #expect(template.displays[0].layout == "tall")
        #expect(template.displays[0].ratio == 0.65)
        #expect(template.displays[0].mainCount == 2)
        #expect(template.windows.map(\.windowID) == [7, 3])
        #expect(template.windows[0].fullscreen)
        #expect(!template.windows[0].minimized)
        #expect(template.windows[0].focused)
        #expect(template.windows[1].minimized)
        #expect(template.windows[1].zoomed)
        #expect(template.windows[1].document == "file:///tmp/draft.txt")
    }

    @Test func hiddenWorkspacesAndOtherSpacesStayOutUnlessFullscreen() throws {
        var savedFacts = facts()
        savedFacts.hiddenWorkspaceWindows = [8, 7]
        let hidden = observed(id: 8, title: "Hidden")
        let fullscreen = observed(id: 7, title: "Show", fullscreen: true)
        let elsewhere = observed(id: 9, title: "Away", spaces: [99])
        let current = observed(id: 3, title: "Here", minimized: true)
        let template = try TemplateCaptureAssembler.make(facts: savedFacts,
                                                          batch: .init(windows: [hidden, fullscreen, elsewhere, current], focusedID: 3, complete: true))
        #expect(template.windows.map(\.windowID) == [3, 7])
        #expect(template.windows[0].focused)
    }

    @Test func fullscreenUsesTheNaturalFrameAndFloatingFollowsTheVisibleFrame() throws {
        var savedFacts = facts()
        savedFacts.virtualWorkspaces = false
        savedFacts.naturalFrames = [5: CGRect(x: 0, y: 0, width: 1000, height: 800), 6: CGRect(x: 1, y: 1, width: 900, height: 700)]
        savedFacts.monitorForTiled = [1: "desk"]
        savedFacts.knownFloating = [1: false, 2: true]
        let fullscreen = observed(id: 5, frame: CGRect(x: 12, y: 12, width: 40, height: 40), fullscreen: true)
        let normal = observed(id: 6, frame: CGRect(x: 30, y: 40, width: 300, height: 200))
        let tiled = observed(id: 1, frame: CGRect(x: 1100, y: 20, width: 200, height: 200))
        let floating = observed(id: 2, frame: CGRect(x: 1100, y: 20, width: 200, height: 200))
        let template = try TemplateCaptureAssembler.make(facts: savedFacts,
                                                          batch: .init(windows: [fullscreen, normal, tiled, floating], focusedID: nil, complete: true))
        #expect(template.windows.first { $0.windowID == 5 }?.frame == CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(template.windows.first { $0.windowID == 6 }?.frame == CGRect(x: 30, y: 40, width: 300, height: 200))
        #expect(template.windows.first { $0.windowID == 1 }?.display == "desk")
        #expect(template.windows.first { $0.windowID == 2 }?.display == "lap")
    }

    @Test func emptyAndIncompleteCapturesDoNotBecomeTemplates() {
        #expect(throws: WindowManager.TemplateError.empty) {
            try TemplateCaptureAssembler.make(facts: facts(), batch: .init(windows: [], focusedID: nil, complete: true))
        }
        #expect(throws: WindowManager.TemplateError.incomplete) {
            try TemplateCaptureAssembler.make(facts: facts(), batch: .init(windows: [observed(id: 3)], focusedID: nil, complete: false))
        }
    }

    @Test @MainActor func lateScreenshotAttachesWithoutReplacingWorkspaceData() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let library = scratch.library()
        var saved = sample()
        #expect(library.save(saved))
        let generation = library.generation(of: saved.id)
        #expect(library.attachScreenshot(Data([9, 9]), to: saved.id, generation: generation))
        #expect(library.templates[0].screenshot == Data([9, 9]))
        #expect(library.templates[0].windows[0].title == "Draft")
        #expect(!library.attachScreenshot(Data([8]), to: saved.id, generation: generation))
        #expect(library.templates[0].screenshot == Data([9, 9]))
        saved.windows[0].title = "Newer"
        #expect(library.save(saved))
        #expect(!library.attachScreenshot(Data([1]), to: saved.id, generation: generation))
        #expect(library.templates[0].windows[0].title == "Newer")
        #expect(library.templates[0].screenshot == Data([9, 9]))
    }

    @Test @MainActor func renameDropsPendingScreenshotAndDeleteDoesNotResurrect() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let library = scratch.library()
        var saved = sample()
        #expect(library.save(saved))
        let generation = library.generation(of: saved.id)
        saved.name = "Research"
        #expect(library.save(saved))
        #expect(!library.attachScreenshot(Data([4]), to: saved.id, generation: generation))
        #expect(library.templates[0].name == "Research")
        #expect(library.templates[0].screenshot == nil)
        let renamed = library.generation(of: saved.id)
        library.delete(saved)
        #expect(!library.attachScreenshot(Data([4]), to: saved.id, generation: renamed))
        #expect(!library.attachScreenshot(Data([4]), to: saved.id, generation: library.generation(of: saved.id)))
        #expect(library.templates.isEmpty)
        #expect(TemplateLibrary(url: scratch.url).templates.isEmpty)
    }

    @Test @MainActor func updateSavesBeforeScreenshotAndKeepsTheOldPreview() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let library = scratch.library()
        var saved = sample()
        saved.screenshot = Data([3])
        #expect(library.save(saved))
        let pause = Pause()
        defer { pause.release() }
        let entered = Flag()
        library.captureWorkspace = {
            var copy = sample()
            copy.windows[0].title = "Fresh"
            return copy
        }
        library.captureScreenshot = {
            entered.value = true
            await pause.wait()
            return Data([7])
        }
        let task = library.update(saved)
        let deadline = Date().addingTimeInterval(2)
        while !entered.value, Date() < deadline { await Task.yield() }
        #expect(entered.value)
        #expect(!library.updating)
        #expect(!library.restoring)
        #expect(library.templates[0].windows[0].title == "Fresh")
        #expect(library.templates[0].screenshot == Data([3]))
        #expect(library.templates[0].id == saved.id)
        pause.release()
        await task.value
        #expect(library.templates[0].screenshot == Data([7]))
        #expect(library.templates[0].windows[0].title == "Fresh")
        #expect(!library.updating)
    }

    @Test @MainActor func staleScreenshotAfterUpdateDoesNotReplaceNewerWindows() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sample()
        #expect(library.save(saved))
        let first = Pause()
        let second = Pause()
        defer { first.release(); second.release() }
        let shots = Counter()
        let phase = Counter()
        library.captureWorkspace = {
            let turn = phase.bump()
            return sample(title: "Snapshot \(turn)")
        }
        library.captureScreenshot = {
            let turn = shots.bump()
            if turn == 1 {
                await first.wait()
                return Data([1])
            }
            await second.wait()
            return Data([2])
        }
        let firstTask = library.update(saved)
        let deadline = Date().addingTimeInterval(2)
        while shots.value < 1, Date() < deadline { await Task.yield() }
        #expect(!library.updating)
        let secondTask = library.update(saved)
        while shots.value < 2, Date() < deadline { await Task.yield() }
        #expect(library.templates[0].windows[0].title == "Snapshot 2")
        first.release()
        await firstTask.value
        #expect(library.templates[0].windows[0].title == "Snapshot 2")
        #expect(library.templates[0].screenshot == nil)
        second.release()
        await secondTask.value
        #expect(library.templates[0].screenshot == Data([2]))
        #expect(library.templates[0].windows[0].title == "Snapshot 2")
        #expect(library.templates[0].id == saved.id)
    }

    @Test @MainActor func deletingDuringScreenshotDoesNotResurrectTheTemplate() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sample()
        #expect(library.save(saved))
        let pause = Pause()
        defer { pause.release() }
        let entered = Flag()
        library.captureWorkspace = { sample(title: "Fresh") }
        library.captureScreenshot = {
            entered.value = true
            await pause.wait()
            return Data([5])
        }
        let task = library.update(saved)
        let deadline = Date().addingTimeInterval(2)
        while !entered.value, Date() < deadline { await Task.yield() }
        library.delete(saved)
        pause.release()
        await task.value
        #expect(library.templates.isEmpty)
        #expect(TemplateLibrary(url: scratch.url).templates.isEmpty)
    }

    @Test @MainActor func incompleteCaptureDoesNotReplaceTheSavedTemplate() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sample()
        #expect(library.save(saved))
        let generation = library.generation(of: saved.id)
        library.captureWorkspace = { throw WindowManager.TemplateError.incomplete }
        library.captureScreenshot = { Data([1]) }
        await library.update(saved).value
        #expect(library.templates[0].windows[0].title == "Draft")
        #expect(library.templates[0].screenshot == nil)
        #expect(library.generation(of: saved.id) == generation)
        #expect(library.error == WindowManager.TemplateError.incomplete.errorDescription)
        #expect(!library.updating)
        #expect(TemplateLibrary(url: scratch.url).templates[0].windows[0].title == "Draft")
    }

    @Test @MainActor func deleteOrRenameDuringSnapshotIsNotWrittenBack() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sample()
        #expect(library.save(saved))
        let pause = Pause()
        defer { pause.release() }
        let entered = Flag()
        library.captureWorkspace = {
            entered.value = true
            await pause.wait()
            return sample(title: "Stale")
        }
        library.captureScreenshot = { Data([9]) }
        let deleted = library.update(saved)
        let deadline = Date().addingTimeInterval(2)
        while !entered.value, Date() < deadline { await Task.yield() }
        library.delete(saved)
        pause.release()
        await deleted.value
        #expect(library.templates.isEmpty)
        #expect(TemplateLibrary(url: scratch.url).templates.isEmpty)

        let renamedLibrary = scratch.library()
        var renamed = sample()
        #expect(renamedLibrary.save(renamed))
        let renamePause = Pause()
        defer { renamePause.release() }
        let renameEntered = Flag()
        renamedLibrary.captureWorkspace = {
            renameEntered.value = true
            await renamePause.wait()
            return sample(title: "Stale")
        }
        renamedLibrary.captureScreenshot = { Data([9]) }
        let renameTask = renamedLibrary.update(renamed)
        let renameDeadline = Date().addingTimeInterval(2)
        while !renameEntered.value, Date() < renameDeadline { await Task.yield() }
        renamed.name = "Research"
        #expect(renamedLibrary.save(renamed))
        renamePause.release()
        await renameTask.value
        #expect(renamedLibrary.templates.count == 1)
        #expect(renamedLibrary.templates[0].name == "Research")
        #expect(renamedLibrary.templates[0].windows[0].title == "Draft")
        #expect(renamedLibrary.templates[0].screenshot == nil)
        #expect(TemplateLibrary(url: scratch.url).templates[0].name == "Research")
    }

    @Test @MainActor func olderScreenshotDoesNotClearANewerSnapshot() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sample()
        #expect(library.save(saved))
        let shotPause = Pause()
        let snapshotPause = Pause()
        defer { shotPause.release(); snapshotPause.release() }
        let shotEntered = Flag()
        let snapshotEntered = Flag()
        let phase = Counter()
        library.captureWorkspace = {
            let turn = phase.bump()
            if turn == 1 { return sample(title: "First") }
            snapshotEntered.value = true
            await snapshotPause.wait()
            return sample(title: "Second")
        }
        library.captureScreenshot = {
            shotEntered.value = true
            await shotPause.wait()
            return Data([1])
        }
        let first = library.update(saved)
        let deadline = Date().addingTimeInterval(2)
        while !shotEntered.value, Date() < deadline { await Task.yield() }
        #expect(!library.updating)
        let second = library.update(saved)
        while !snapshotEntered.value, Date() < deadline { await Task.yield() }
        #expect(library.updating)
        shotPause.release()
        await first.value
        #expect(library.updating)
        #expect(library.templates[0].windows[0].title == "First")
        snapshotPause.release()
        await second.value
        #expect(!library.updating)
        #expect(library.templates[0].windows[0].title == "Second")
        #expect(library.templates[0].id == saved.id)
    }
}

private func app(pid: pid_t) -> TemplateAppSnapshot {
    TemplateAppSnapshot(pid: pid, bundleID: "com.example.\(pid)", name: "App \(pid)", launchDate: nil)
}

private func observed(id: CGWindowID, title: String = "Window", frame: CGRect = CGRect(x: 40, y: 40, width: 600, height: 400),
                      minimized: Bool = false, fullscreen: Bool = false, spaces: [UInt64] = [1]) -> TemplateObservedWindow {
    TemplateObservedWindow(pid: 20, bundleID: "com.example.editor", appName: "Editor", title: title,
                           document: title == "Draft" ? "file:///tmp/draft.txt" : nil, frame: frame, minimized: minimized,
                           fullscreen: fullscreen, resizable: true, windowID: id, launchDate: Date(timeIntervalSince1970: 100), spaces: spaces)
}

private func facts(order: [CGWindowID] = []) -> TemplateCaptureFacts {
    TemplateCaptureFacts(tilingEnabled: true, displays: [
        .init(id: "desk", name: "Desk", frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
              visible: CGRect(x: 0, y: 24, width: 1000, height: 776), isMain: true, layout: "tall", ratio: 0.65, mainCount: 2),
        .init(id: "lap", name: "Laptop", frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
              visible: CGRect(x: 1000, y: 24, width: 800, height: 576), isMain: false, layout: "floating", ratio: 0.5, mainCount: 1),
    ], zoomed: [:], order: order, currentSpaces: [1], hiddenWorkspaceWindows: [], monitorForTiled: [:], virtualWorkspaces: true,
                         knownFloating: [:], naturalFrames: [:], fallbackFocus: nil)
}

private func sample(title: String = "Draft") -> WorkspaceTemplate {
    WorkspaceTemplate(name: "Writing", tilingEnabled: true, displays: [
        .init(id: "desk", name: "Desk", frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
              visible: CGRect(x: 0, y: 24, width: 1000, height: 776), isMain: true, layout: "tall", ratio: 0.65, mainCount: 2),
    ], windows: [
        .init(bundleID: "com.example.editor", appName: "Editor", title: title, document: "file:///tmp/draft.txt",
              display: "desk", frame: CGRect(x: 0, y: 24, width: 650, height: 776), floating: false, minimized: false,
              fullscreen: false, zoomed: false, focused: true, windowID: 42, launchDate: nil),
    ])
}

private struct Scratch {
    let url: URL
    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        url = directory.appendingPathComponent("templates.json")
    }
    func library() -> TemplateLibrary { TemplateLibrary(url: url) }
    func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

private final class Pause: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        released = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int { lock.withLock { stored } }
    @discardableResult
    func bump() -> Int { lock.withLock { stored += 1; return stored } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
