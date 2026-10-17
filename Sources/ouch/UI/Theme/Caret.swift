import AppKit
import CoreText
import SwiftUI

enum Caret: Equatable {
    case none
    case top(CGFloat)
    case bottom
    case bottomAt(CGFloat)
    case leading(CGFloat)
    case leadingBottom(CGFloat)
}
