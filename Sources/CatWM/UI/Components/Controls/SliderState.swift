import AppKit
import SwiftUI

final class SliderState: ObservableObject {
    @Published var dragging = false
    @Published var fraction: Double?
    @Published var stretch: CGFloat = 0
    @Published var hovering = false
    var start: Double = 0
    var moved = false
}
