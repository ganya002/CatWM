import AppKit
import Combine

final class TemplateLibrary: ObservableObject {
    static let shared = TemplateLibrary()
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ouch/templates.json")

    @Published private(set) var templates: [WorkspaceTemplate] = []
    @Published var draft: WorkspaceTemplate?
    @Published var preview: WorkspaceTemplate?
    @Published var error: String?
    @Published var status: String?
    @Published private(set) var restoring = false
    @Published private(set) var updating = false
    private let url: URL
    private var readProblem: String?
    private var restoreTask: Task<Void, Never>?

    struct Stored: Codable {
        var version = 1
        var templates: [WorkspaceTemplate]
    }

    init(url: URL = TemplateLibrary.url) {
        self.url = url
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: url))
            guard stored.version == 1 else {
                readProblem = "This template file needs a newer version of Ouch."
                error = readProblem
                return
            }
            templates = stored.templates
        } catch let problem as NSError where problem.domain == NSCocoaErrorDomain && problem.code == NSFileReadNoSuchFileError {
        } catch {
            readProblem = "Ouch could not read your templates: \(error.localizedDescription)"
            self.error = readProblem
        }
    }

    func nameProblem(_ name: String, id: UUID) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a template name." }
        if templates.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "A template already uses this name."
        }
        return nil
    }

    @discardableResult
    func save(_ template: WorkspaceTemplate) -> Bool {
        guard nameProblem(template.name, id: template.id) == nil else { return false }
        var copy = template
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = templates.filter { $0.id != copy.id }
        updated.append(copy)
        return persist(updated.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    func update(_ template: WorkspaceTemplate) {
        guard !updating, !restoring else { return }
        do {
            var copy = try WindowManager.shared.captureTemplate()
            copy.id = template.id
            copy.name = template.name
            copy.createdAt = template.createdAt
            updating = true
            Task { @MainActor in
                defer { updating = false }
                copy.screenshot = await TemplateScreenshot.capture()
                if save(copy) {
                    status = copy.screenshot == nil ? "Updated \(copy.name) without a screenshot. Allow screen recording, then update the template to add one." : "Updated \(copy.name)."
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ template: WorkspaceTemplate) {
        if persist(templates.filter { $0.id != template.id }) { status = "Deleted \(template.name)." }
    }

    private func persist(_ updated: [WorkspaceTemplate]) -> Bool {
        if let readProblem { error = readProblem; return false }
        do {
            let data = try JSONEncoder().encode(Stored(templates: updated))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            templates = updated
            error = nil
            return true
        } catch {
            self.error = "Ouch could not save your templates: \(error.localizedDescription)"
            return false
        }
    }

    func restore(_ template: WorkspaceTemplate) {
        guard !restoring, !updating else { return }
        restoring = true
        error = nil
        status = "Opening \(template.name)…"
        restoreTask = Task { @MainActor in
            defer { restoring = false; restoreTask = nil }
            do {
                let result = try await TemplateRestorer(template: template).restore()
                status = result
                HUD.shared.show(result, on: nil)
            } catch is CancellationError {
                status = "Template restore stopped."
            } catch {
                self.error = error.localizedDescription
                status = nil
            }
        }
    }

    func cancelRestore() { restoreTask?.cancel() }
}
