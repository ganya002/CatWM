import AppKit
import SwiftUI

final class ModeFXModel: ObservableObject {
    @Published var active = false
    @Published var enters = 0
    @Published var style: ModeFX.Style = .draw
    @Published var color = Theme.accent
    var cursor: CGPoint = .zero
}
