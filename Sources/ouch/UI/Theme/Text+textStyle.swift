import AppKit
import CoreText
import SwiftUI

extension Text {
    func textStyle(_ style: TextStyle) -> Text { font(style.font).tracking(style.tracking) }
}
