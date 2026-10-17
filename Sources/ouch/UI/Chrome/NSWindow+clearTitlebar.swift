import AppKit
import SwiftUI

extension NSWindow {
    func clearTitlebar(hiding buttons: [NSWindow.ButtonType]) {
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for b in buttons { standardWindowButton(b)?.isHidden = true }
    }
}
