import AppKit
import CoreText
import SwiftUI

extension View {
    func floatingGlass<S: InsettableShape>(_ shape: S) -> some View { modifier(FloatingGlass(shape: shape)) }
}
