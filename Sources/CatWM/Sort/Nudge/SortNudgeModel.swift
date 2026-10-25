import AppKit
import SwiftUI

final class SortNudgeModel: ObservableObject {
    @Published var workspace = ""
    @Published var count = 0
    @Published var keys: [String] = []
    @Published var caret: CGFloat = 40
    var sort: () -> Void = {}
    var later: () -> Void = {}
    var never: () -> Void = {}
}
