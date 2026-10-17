import AppKit
import SwiftUI

func confirm(_ title: String, _ detail: String, button: String = "Reset") -> Bool {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = detail
    a.addButton(withTitle: button)
    a.addButton(withTitle: "Cancel")
    a.buttons.first?.hasDestructiveAction = true
    return a.runModal() == .alertFirstButtonReturn
}
