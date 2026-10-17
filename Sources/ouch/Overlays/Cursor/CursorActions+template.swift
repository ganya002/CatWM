import AppKit

extension CursorActions {
    func beginTemplateSave() {
        guard model.open, model.templateDraft == nil else { return }
        do {
            model.templateDraft = try WindowManager.shared.captureTemplate()
            model.templateName = ""
            model.saveError = nil
            model.capturing = true
            Hotkeys.shared.textInputActive = true
            resizeMenu()
            menuPanel?.makeKey()
            let id = model.templateDraft?.id
            screenshotTask = Task { @MainActor [weak self] in
                let screenshot = await TemplateScreenshot.capture()
                guard let self, !Task.isCancelled, model.templateDraft?.id == id else { return }
                model.templateDraft?.screenshot = screenshot
                model.capturing = false
                screenshotTask = nil
                menuPanel?.makeKey()
            }
        } catch {
            HUD.shared.show(error.localizedDescription, on: nil)
        }
    }

    func saveTemplate() {
        guard var template = model.templateDraft, !model.capturing, model.nameProblem == nil else { return }
        template.name = model.templateName
        let library = TemplateLibrary.shared
        guard library.save(template) else { model.saveError = library.error; return }
        let name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        library.status = template.screenshot == nil ? "Saved \(name) without a screenshot. Allow screen recording, then update the template to add one." : "Saved \(name)."
        dismissMenu()
        HUD.shared.show("Saved \(name)", on: nil)
    }

    func cancelTemplateSave() {
        resetTemplateSave()
        resizeMenu()
    }

    func resetTemplateSave() {
        screenshotTask?.cancel()
        screenshotTask = nil
        model.templateDraft = nil
        model.templateName = ""
        model.saveError = nil
        model.capturing = false
        Hotkeys.shared.textInputActive = false
    }

    private func resizeMenu() {
        guard let menu = menuPanel else { return }
        let point = CGPoint(x: menu.frame.minX + model.anchor.x, y: menu.frame.maxY - model.anchor.y)
        place(menu: menu, at: point)
    }
}
