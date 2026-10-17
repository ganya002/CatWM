import AppKit
import SwiftUI

final class CycleDrag: ObservableObject {
    @Published var layout: Layout?
    @Published var x: CGFloat = 0
    var origin = 0
}
