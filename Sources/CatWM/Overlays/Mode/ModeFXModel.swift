import AppKit
import SwiftUI

final class ModeFXModel: ObservableObject {
    @Published var active = false
    @Published var enters = 0
    @Published var style: ModeFX.Style = .draw
    @Published var color = Theme.accent
    var cursor: CGPoint = .zero
}

final class ModeFXScreen: ObservableObject {
    @Published private(set) var shape: ScreenShape
    @Published private(set) var origin: CGPoint

    init(_ screen: NSScreen) {
        shape = .of(screen)
        origin = screen.frame.origin
    }

    func update(_ screen: NSScreen) {
        let next = ScreenShape.of(screen)
        if next != shape { shape = next }
        if screen.frame.origin != origin { origin = screen.frame.origin }
    }
}
