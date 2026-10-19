import AppKit
import SwiftUI

struct OMenuRowStyle: ButtonStyle {
    static let inset: CGFloat = 10
    var highlight = MenuRowHighlight.followsHover
    var open = false
    var danger = false
    var bare = false

    func makeBody(configuration: Configuration) -> some View { OMenuRowBody(configuration: configuration, style: self) }
}
