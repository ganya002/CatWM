import AppKit
import SwiftUI

final class Coach {
    enum Target { case center, window, bar, mode }
    enum Event { case mode(String), command(String, String, inMode: Bool), tick }
    enum Ending { case finished, skipped, paused, tutorial }

    struct Step {
        var title: String
        var text: String
        var target = Target.center
        var caps: [String] = []
        var tokens: [String] = []
        var button: String?
        var needsMode = false
        var recall = false
        var count = 1
        var accept: (Event) -> String? = { _ in nil }
        var simulate: (() -> Void)?
        var summary: Summary?
        var final: Bool { summary != nil }
    }

    struct SummaryGroup {
        var title: String
        var column = 1
        var rows: [(caps: [String], label: String)]
    }

    struct Summary {
        var modeCaps: [String] = []
        var modeName = ""
        var groups: [SummaryGroup] = []
        var helpKey: String?
        var tutorial = false
    }

    let windowManager = WindowManager.shared
    weak var statusButton: NSStatusBarButton?
    let lesson: Lesson
    let onEnd: (Ending) -> Void
    let screen: NSScreen

    var desk: String?
    var other: String?
    var sendTo: String?
    var original: String?
    var book = BindBook(binds: [])

    var index = 0
    var step: Step?
    var done = false
    var hits = 0
    var seen: Set<String> = []
    var ended = false
    var hintWork: DispatchWorkItem?

    var helper: Process?
    var helperPID: pid_t = 0

    var panel: OuchPanel?
    var host: OuchHostingView<CoachCardView>?
    let model = CoachModel()
    var follow: Timer?
    var target = NSRect.zero

    var practiceWindows: [AXUIElement] {
        guard helperPID > 0 else { return [] }
        return AXUIElementCreateApplication(helperPID).elements(kAXWindowsAttribute)
    }

    var focusedPractice: AXUIElement? {
        helperPID > 0 ? AXUIElementCreateApplication(helperPID).element(kAXFocusedWindowAttribute) : nil
    }

    var focusedTitle: String? { focusedPractice?.string(kAXTitleAttribute) }

    var visibleTitles: [String] {
        practiceWindows.compactMap { window -> (String, CGFloat)? in
            guard let title = window.string(kAXTitleAttribute), let frame = onScreen(window) else { return nil }
            return (title, frame.minX)
        }
        .sorted { $0.1 < $1.1 }.map(\.0)
    }

    var mainTitle: String? {
        practiceWindows.compactMap { window -> (String, CGFloat)? in
            guard let title = window.string(kAXTitleAttribute), let frame = onScreen(window) else { return nil }
            return (title, frame.width * frame.height)
        }
        .max { $0.1 < $1.1 }?.0
    }

    init?(lesson: Lesson, statusButton: NSStatusBarButton?, onEnd: @escaping (Ending) -> Void) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        self.lesson = lesson
        self.statusButton = statusButton
        self.onEnd = onEnd
        self.screen = screen
    }
}
