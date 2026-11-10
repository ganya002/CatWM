import AppKit
import CatWMKit

extension TemplateLibrary {
    func quickActions() -> [QuickAction] {
        if restoring {
            return [QuickAction(id: "template.stop", title: "Stop opening template") { [weak self] in
                self?.cancelRestore()
            }]
        }
        if updating { return [] }
        var actions = [QuickAction(id: "template.save", title: "Save workspace…",
                                   keys: ["S"], keyCode: keyCodes["s"]) {
            CursorActions.shared.beginTemplateSave()
        }]
        for (index, template) in templates.enumerated() {
            let key = index < 9 ? String(index + 1) : nil
            actions.append(QuickAction(id: "template.\(template.id)", title: template.name,
                                       keys: key.map { [$0] } ?? [], keyCode: key.flatMap { keyCodes[$0] },
                                       remove: { [weak self] in self?.delete(template) },
                                       run: { [weak self] in self?.restore(template) }))
        }
        return actions
    }
}
