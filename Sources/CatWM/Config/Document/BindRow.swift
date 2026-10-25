import AppKit
import Carbon
import Combine
import SwiftUI

struct BindRow: Identifiable, Equatable {
    let id = UUID()
    var mods: String
    var key: String
    var dispatcher: String
    var args: String
    var submap = ""
    var kind = "bind"
}
