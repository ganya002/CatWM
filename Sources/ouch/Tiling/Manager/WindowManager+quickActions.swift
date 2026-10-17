import AppKit

extension WindowManager {
    func quickActions() -> (title: String, actions: [QuickAction])? {
        guard isStarted else { return nil }
        return ("Workspace templates", TemplateLibrary.shared.quickActions() + FocusDim.quickActions())
    }
}
