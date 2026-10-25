import AppKit
import SwiftUI

final class MenuBarTipModel: ObservableObject {
    enum State { case move, good, hidden }
    @Published var state = State.move
    @Published var caret: CGFloat?
}
