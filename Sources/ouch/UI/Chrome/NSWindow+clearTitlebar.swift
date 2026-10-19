import AppKit
import SwiftUI

extension NSWindow {
    func clearTitlebar(hiding buttons: [NSWindow.ButtonType]) {
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in buttons { standardWindowButton(button)?.isHidden = true }
    }
}
