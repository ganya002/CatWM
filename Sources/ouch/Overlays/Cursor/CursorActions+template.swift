import AppKit

enum TemplatePreviewState: Equatable, Sendable {
    case waiting
    case ready(Data?)
}

final class TemplatePreviewJob: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TemplatePreviewState = .waiting
    private var waiter: CheckedContinuation<Data?, Never>?

    func state() -> TemplatePreviewState { lock.withLock { stored } }

    func finish(_ data: Data?) { settle(.ready(data)) }

    func cancel() { settle(.ready(nil)) }

    func result() async -> Data? {
        if case .ready(let data) = state() { return data }
        return await withCheckedContinuation { continuation in
            lock.lock()
            if case .ready(let data) = stored {
                lock.unlock()
                continuation.resume(returning: data)
                return
            }
            waiter = continuation
            lock.unlock()
        }
    }

    private func settle(_ state: TemplatePreviewState) {
        lock.lock()
        guard case .waiting = stored else {
            lock.unlock()
            return
        }
        stored = state
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        if case .ready(let data) = state { waiter?.resume(returning: data) }
    }
}

extension CursorActions {
    func deleteTemplate(_ action: QuickAction) {
        guard let remove = action.remove else { return }
        remove()
        if let found = WindowManager.shared.quickActions() {
            model.title = found.title
            model.actions = found.actions
            model.hovered = nil
            resizeMenu()
            DispatchQueue.main.async { [weak self] in
                DispatchQueue.main.async { self?.notePointer(at: NSEvent.mouseLocation) }
            }
        }
        if let error = TemplateLibrary.shared.error { HUD.shared.show(error, on: nil) }
    }

    func beginTemplateSave() {
        guard model.open, model.templateDraft == nil else { return }
        model.snapshotTask?.cancel()
        if model.previewJob != nil {
            screenshotTask?.cancel()
            model.previewJob?.cancel()
        }
        screenshotTask = nil
        model.templateSaveGeneration += 1
        let generation = model.templateSaveGeneration
        let job = TemplatePreviewJob()
        model.previewJob = job
        model.templateDraft = WorkspaceTemplate(name: "", tilingEnabled: WindowManager.shared.tilingEnabled, displays: [], windows: [])
        model.templateName = ""
        model.saveError = nil
        model.snapshotReady = false
        model.capturing = true
        Hotkeys.shared.textInputActive = true
        resizeMenu()
        menuPanel?.makeKey()
        model.snapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let captured = try await WindowManager.shared.captureTemplate()
                guard generation == model.templateSaveGeneration else { return }
                var copy = captured
                if case .ready(let shot) = job.state() { copy.screenshot = shot }
                model.templateDraft = copy
                model.snapshotReady = true
                model.saveError = nil
                menuPanel?.makeKey()
            } catch {
                guard generation == model.templateSaveGeneration else { return }
                model.saveError = error.localizedDescription
                model.snapshotReady = false
            }
        }
        screenshotTask = Task { @MainActor [weak self] in
            let shot = await TemplateScreenshot.capture()
            if Task.isCancelled {
                job.cancel()
                return
            }
            job.finish(shot)
            guard let self, generation == model.templateSaveGeneration else { return }
            model.capturing = false
            guard model.snapshotReady, var draft = model.templateDraft else { return }
            draft.screenshot = shot
            model.templateDraft = draft
        }
    }

    func saveTemplate() {
        guard model.snapshotReady, var template = model.templateDraft, model.nameProblem == nil else { return }
        template.name = model.templateName
        let preview = model.previewJob
        var waiting = false
        if let preview {
            switch preview.state() {
            case .ready(let shot): template.screenshot = shot
            case .waiting: waiting = true
            }
        }
        let library = TemplateLibrary.shared
        guard library.save(template) else { model.saveError = library.error; return }
        let id = template.id
        let generation = library.generation(of: id)
        let name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        waiting = waiting && template.screenshot == nil
        model.previewJob = nil
        screenshotTask = nil
        dismissMenu()
        HUD.shared.show("Saved \(name)", on: nil)
        guard waiting, let preview else {
            library.status = template.screenshot == nil ? "Saved \(name) without a screenshot. Allow screen recording, then update the template to add one." : "Saved \(name)."
            return
        }
        library.status = "Saved \(name)."
        Task { @MainActor in
            let shot = await preview.result()
            if let shot, !shot.isEmpty, library.attachScreenshot(shot, to: id, generation: generation) {
                library.status = "Saved \(name)."
                return
            }
            guard library.generation(of: id) == generation, library.templates.contains(where: { $0.id == id }) else { return }
            library.status = "Saved \(name) without a screenshot. Allow screen recording, then update the template to add one."
        }
    }

    func cancelTemplateSave() {
        resetTemplateSave()
        resizeMenu()
    }

    func resetTemplateSave() {
        model.templateSaveGeneration += 1
        model.snapshotTask?.cancel()
        model.snapshotTask = nil
        if model.previewJob != nil {
            screenshotTask?.cancel()
            model.previewJob?.cancel()
        }
        screenshotTask = nil
        model.previewJob = nil
        model.templateDraft = nil
        model.templateName = ""
        model.saveError = nil
        model.capturing = false
        model.snapshotReady = false
        Hotkeys.shared.textInputActive = false
    }

    private func resizeMenu() {
        guard let menu = menuPanel else { return }
        let point = CGPoint(x: menu.frame.minX + model.anchor.x, y: menu.frame.maxY - model.anchor.y)
        place(menu: menu, at: point)
    }
}
