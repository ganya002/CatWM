import AppKit
import SwiftUI

struct SettingEntry: Identifiable {
    let id: String
    let title: String
    let pane: Pane
    var advanced = false
    var keywords = ""
    var bind: BindRow? = nil
}
