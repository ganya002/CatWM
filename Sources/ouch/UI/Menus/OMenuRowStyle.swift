import AppKit
import SwiftUI

struct OMenuRowStyle: ButtonStyle {
    var highlighted: Bool? = nil
    var open = false
    var danger = false
    var bare = false

    func makeBody(configuration: Configuration) -> some View { OMenuRowBody(configuration: configuration, style: self) }
}
