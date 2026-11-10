import AppKit
import CatWMKit
import SwiftUI

final class PanelMotionDemo {
    static let shared = PanelMotionDemo()
    private(set) var preview: PanelMotion?
    private var work: [DispatchWorkItem] = []

    func command(_ args: [String]) {
        switch args.first?.lowercased() {
        case "all": play(PanelMotion.allCases)
        case let name? where PanelMotion(rawValue: name) != nil: play(PanelMotion(rawValue: name).map { [$0] } ?? [])
        default: Log.info("panelfx: styles are \(PanelMotion.allCases.map(\.rawValue).joined(separator: ", ")), or all")
        }
    }

    func play(_ styles: [PanelMotion], keyboardOnly: Bool = false) {
        work.forEach { $0.cancel() }
        work = []
        KeyHelp.shared.hide()
        let mode = ShortcutIndex().modeName
        var time = 0.0
        for style in styles {
            if keyboardOnly {
                at(time + 0.3) { self.preview = style; KeyHelp.shared.showFromMenu(preferredMode: mode) }
                at(time + 2.2) { KeyHelp.shared.hide() }
                time += 2.6
            } else {
                at(time) { self.preview = style; HUD.shared.show(style.title, on: NSScreen.main) }
                at(time + 1.0) { SortPanel.shared.open() }
                at(time + 2.9) { SortPanel.shared.finish() }
                at(time + 3.6) { KeyHelp.shared.showFromMenu(preferredMode: mode) }
                at(time + 5.6) { KeyHelp.shared.hide() }
                time += 6.4
            }
        }
        at(time) { self.preview = nil }
    }

    private func at(_ delay: Double, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        work.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
