import AppKit
import SwiftUI

final class WhatsNewModel: ObservableObject {
    @Published var versions = ""
    @Published var features: [Release.Feature] = []
    @Published var caret: CGFloat?
    var canTour: Bool { features.contains { $0.tour != nil } }
    var close: () -> Void = {}
    var tour: () -> Void = {}
    var run: (() -> Void) -> Void = { _ in }
}
