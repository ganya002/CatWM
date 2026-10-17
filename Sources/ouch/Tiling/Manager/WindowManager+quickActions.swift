import AppKit

extension WindowManager {
    func quickActions() -> (title: String, actions: [QuickAction])? {
        guard isStarted else { return nil }
        let library = TemplateLibrary.shared
        var actions: [QuickAction] = []
        if !library.restoring, !library.updating {
            actions.append(QuickAction(id: "template.save", title: "Save workspace…", symbol: "plus",
                                       keys: ["S"], keyCode: keyCodes["s"]) {
                CursorActions.shared.beginTemplateSave()
            })
            for (index, template) in library.templates.enumerated() {
                let key = index < 9 ? String(index + 1) : nil
                actions.append(QuickAction(id: "template.\(template.id)", title: template.name, symbol: "rectangle.3.group",
                                           keys: key.map { [$0] } ?? [], keyCode: key.flatMap { keyCodes[$0] }) {
                    library.restore(template)
                })
            }
        } else if library.restoring {
            actions.append(QuickAction(id: "template.stop", title: "Stop opening template", symbol: "stop") { library.cancelRestore() })
        }
        actions.append(QuickAction(id: "focus.dim", title: "Dim other windows", symbol: "circle.lefthalf.filled",
                                   keys: ["D"], keyCode: keyCodes["d"], isOn: FocusDim.shared.dims) {
            self.dispatch("toggledim", "")
        })
        actions.append(QuickAction(id: "focus.blur", title: "Blur other windows", symbol: "drop.halffull",
                                   keys: ["B"], keyCode: keyCodes["b"], isOn: FocusDim.shared.blurs) {
            self.dispatch("toggleblur", "")
        })
        actions.append(QuickAction(id: "template.manage", title: "Manage templates", symbol: "gearshape",
                                   keys: [","], keyCode: keyCodes["comma"]) { SettingsWindow.shared.show(pane: .templates) })
        return ("Workspace templates", actions)
    }
}
