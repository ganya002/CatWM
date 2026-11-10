@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct TemplateLibraryUpdateTests {
    @Test @MainActor func lateScreenshotAttachesWithoutReplacingWorkspaceData() throws {
        let scratch = try TemplateScratch()
        defer { scratch.remove() }
        let library = scratch.library()
        var saved = sampleTemplate()
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

    @Test @MainActor func renameDropsPendingScreenshotAndDeleteDoesNotResurrect() throws {
        let scratch = try TemplateScratch()
        defer { scratch.remove() }
        let library = scratch.library()
        var saved = sampleTemplate()
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
        let scratch = try TemplateScratch()
        defer { scratch.remove() }
        let library = scratch.library()
        var saved = sampleTemplate()
        saved.screenshot = Data([3])
        #expect(library.save(saved))
        let pause = CapturePause()
        defer { pause.release() }
        let entered = CaptureFlag()
        library.captureWorkspace = {
            var copy = sampleTemplate()
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
        let scratch = try TemplateScratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sampleTemplate()
        #expect(library.save(saved))
        let first = CapturePause()
        let second = CapturePause()
        defer { first.release(); second.release() }
        let shots = CaptureCounter()
        let phase = CaptureCounter()
        library.captureWorkspace = {
            let turn = phase.bump()
            return sampleTemplate(title: "Snapshot \(turn)")
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
        let scratch = try TemplateScratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sampleTemplate()
        #expect(library.save(saved))
        let pause = CapturePause()
        defer { pause.release() }
        let entered = CaptureFlag()
        library.captureWorkspace = { sampleTemplate(title: "Fresh") }
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
        let scratch = try TemplateScratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sampleTemplate()
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
        let scratch = try TemplateScratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sampleTemplate()
        #expect(library.save(saved))
        let pause = CapturePause()
        defer { pause.release() }
        let entered = CaptureFlag()
        library.captureWorkspace = {
            entered.value = true
            await pause.wait()
            return sampleTemplate(title: "Stale")
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
        var renamed = sampleTemplate()
        #expect(renamedLibrary.save(renamed))
        let renamePause = CapturePause()
        defer { renamePause.release() }
        let renameEntered = CaptureFlag()
        renamedLibrary.captureWorkspace = {
            renameEntered.value = true
            await renamePause.wait()
            return sampleTemplate(title: "Stale")
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
        let scratch = try TemplateScratch()
        defer { scratch.remove() }
        let library = scratch.library()
        let saved = sampleTemplate()
        #expect(library.save(saved))
        let shotPause = CapturePause()
        let snapshotPause = CapturePause()
        defer { shotPause.release(); snapshotPause.release() }
        let shotEntered = CaptureFlag()
        let snapshotEntered = CaptureFlag()
        let phase = CaptureCounter()
        library.captureWorkspace = {
            let turn = phase.bump()
            if turn == 1 { return sampleTemplate(title: "First") }
            snapshotEntered.value = true
            await snapshotPause.wait()
            return sampleTemplate(title: "Second")
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
