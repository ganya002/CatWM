import AppKit
import Combine

package final class TemplateLibrary: ObservableObject {
    package static let shared = TemplateLibrary()
    package static let url = Instance.configFolder.appendingPathComponent("templates.json")

    @Published package private(set) var templates: [WorkspaceTemplate] = []
    @Published package var draft: WorkspaceTemplate?
    @Published package var preview: WorkspaceTemplate?
    @Published package var error: String?
    @Published package var status: String?
    @Published package private(set) var restoring = false
    @Published package private(set) var updating = false
    private let url: URL
    private var readProblem: String?
    private var restoreTask: Task<Void, Never>?
    private var generations: [UUID: Int] = [:]
    private var workspaceGenerations: [UUID: Int] = [:]
    private var updateToken = 0
    package var captureWorkspace: () async throws -> WorkspaceTemplate = {
        try await WindowManager.shared.captureTemplate()
    }
    package var captureScreenshot: () async -> Data? = {
        await TemplateScreenshot.capture()
    }

    package struct Stored: Codable {
        package var version = 1
        package var templates: [WorkspaceTemplate]
    }

    package init(url: URL = TemplateLibrary.url) {
        self.url = url
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: url))
            guard stored.version == 1 else {
                readProblem = "This template file needs a newer version of CatWM."
                error = readProblem
                return
            }
            templates = stored.templates
        } catch let problem as NSError
                    where problem.domain == NSCocoaErrorDomain && problem.code == NSFileReadNoSuchFileError {
        } catch {
            readProblem = "CatWM could not read your templates: \(error.localizedDescription)"
            self.error = readProblem
        }
    }

    package func nameProblem(_ name: String, id: UUID) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a template name." }
        if templates.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "A template already uses this name."
        }
        return nil
    }

    @discardableResult
    package func save(_ template: WorkspaceTemplate) -> Bool {
        guard nameProblem(template.name, id: template.id) == nil else { return false }
        var copy = template
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.screenshot == nil { copy.screenshot = templates.first(where: { $0.id == copy.id })?.screenshot }
        var updated = templates.filter { $0.id != copy.id }
        updated.append(copy)
        let sorted = updated.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard persist(sorted) else { return false }
        generations[copy.id, default: 0] += 1
        workspaceGenerations[copy.id, default: 0] += 1
        return true
    }

    package func generation(of id: UUID) -> Int { generations[id] ?? 0 }

    @discardableResult
    package func attachScreenshot(_ data: Data, to id: UUID, generation expected: Int) -> Bool {
        guard !data.isEmpty, generations[id] == expected,
              let index = templates.firstIndex(where: { $0.id == id }) else { return false }
        var updated = templates
        updated[index].screenshot = data
        guard persist(updated) else { return false }
        generations[id] = expected + 1
        return true
    }

    @discardableResult
    package func update(_ template: WorkspaceTemplate) -> Task<Void, Never> {
        guard !updating, !restoring else { return Task {} }
        updateToken += 1
        let token = updateToken
        updating = true
        let id = template.id
        let baseline = workspaceGenerations[id] ?? 0
        return Task { @MainActor in
            func endSnapshot() {
                if updateToken == token { updating = false }
            }
            do {
                var copy = try await captureWorkspace()
                guard !Task.isCancelled, updateToken == token else { endSnapshot(); return }
                guard workspaceGenerations[id, default: 0] == baseline,
                      let current = templates.first(where: { $0.id == id }) else {
                    endSnapshot()
                    return
                }
                copy.id = id
                copy.name = current.name
                copy.createdAt = current.createdAt
                copy.screenshot = current.screenshot
                guard save(copy) else { endSnapshot(); return }
                let expected = generation(of: id)
                let savedName = current.name
                endSnapshot()
                status = "Updated \(savedName)."
                let screenshot = await captureScreenshot()
                guard !Task.isCancelled else { return }
                if let screenshot, !screenshot.isEmpty, attachScreenshot(screenshot, to: id, generation: expected) {
                    status = "Updated \(templates.first(where: { $0.id == id })?.name ?? savedName)."
                    return
                }
                guard generation(of: id) == expected,
                      let current = templates.first(where: { $0.id == id }) else { return }
                if current.screenshot == nil {
                    status = "Updated \(current.name) without a screenshot. "
                        + "Allow screen recording, then update the template to add one."
                }
            } catch is CancellationError {
                endSnapshot()
            } catch {
                self.error = error.localizedDescription
                endSnapshot()
            }
        }
    }

    package func delete(_ template: WorkspaceTemplate) {
        guard persist(templates.filter { $0.id != template.id }) else { return }
        generations[template.id, default: 0] += 1
        workspaceGenerations[template.id, default: 0] += 1
        status = "Deleted \(template.name)."
    }

    private func persist(_ updated: [WorkspaceTemplate]) -> Bool {
        if let readProblem { error = readProblem; return false }
        do {
            let data = try JSONEncoder().encode(Stored(templates: updated))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            templates = updated
            error = nil
            return true
        } catch {
            self.error = "CatWM could not save your templates: \(error.localizedDescription)"
            return false
        }
    }

    package func restore(_ template: WorkspaceTemplate) {
        guard !restoring, !updating else { return }
        restoring = true
        error = nil
        status = "Opening \(template.name)…"
        restoreTask = Task { @MainActor in
            defer { restoring = false; restoreTask = nil }
            do {
                let result = try await TemplateRestorer(template: template).restore()
                status = result
                WindowManager.shared.surface.showHUD(result, on: nil)
            } catch is CancellationError {
                status = "Template restore stopped."
            } catch {
                self.error = error.localizedDescription
                status = nil
            }
        }
    }

    package func cancelRestore() { restoreTask?.cancel() }
}
