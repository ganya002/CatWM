import AppKit
import SwiftUI

struct CursorShortcutSpec: Identifiable {
    let id: String
    let title: String
    let dispatcher: String
    let args: String
    var nextWorkspace = false
}
