import AppKit
import SwiftUI

final class CoachModel: ObservableObject {
    enum Caret: Equatable { case none, up(CGFloat), down }
    @Published var title = ""
    @Published var text = ""
    @Published var caps: [String] = []
    @Published var capsDone: [Bool] = []
    @Published var pressed = false
    @Published var done = false
    @Published var recall = false
    @Published var hidden = false
    @Published var warning: String?
    @Published var button: String?
    @Published var summary: Coach.Summary?
    var final: Bool { summary != nil }
    @Published var canHead = true
    @Published var headLabel = "Skip tour"
    @Published var headSymbol: String?
    @Published var progress: Double = 0
    @Published var caret: Caret = .none
    var tryKeys: () -> Void = {}
    var next: () -> Void = {}
    var headAction: () -> Void = {}
    var reveal: () -> Void = {}
    var tutorial: () -> Void = {}
}
