import AppKit
import SwiftUI

enum PanelMotionDemo {
    private static var work: [DispatchWorkItem] = []

    static func command(_ args: [String]) {
        switch args.first?.lowercased() {
        case "all": play(PanelMotion.allCases)
        case let name? where PanelMotion(rawValue: name) != nil: play([PanelMotion(rawValue: name)!])
        default: Log.info("panelfx: styles are \(PanelMotion.allCases.map(\.rawValue).joined(separator: ", ")), or all")
        }
    }

    static func play(_ styles: [PanelMotion], keyboardOnly: Bool = false) {
        work.forEach { $0.cancel() }
        work = []
        KeyHelp.shared.hide()
        let mode = ShortcutIndex().modeName
        var t = 0.0
        for s in styles {
            if keyboardOnly {
                at(t + 0.3) { PanelMotion.preview = s; KeyHelp.shared.showFromMenu(preferredMode: mode) }
                at(t + 2.2) { KeyHelp.shared.hide() }
                t += 2.6
            } else {
                at(t) { PanelMotion.preview = s; HUD.shared.show(s.title, on: NSScreen.main) }
                at(t + 1.0) { SortPanel.shared.open() }
                at(t + 2.9) { SortPanel.shared.finish() }
                at(t + 3.6) { KeyHelp.shared.showFromMenu(preferredMode: mode) }
                at(t + 5.6) { KeyHelp.shared.hide() }
                t += 6.4
            }
        }
        at(t) { PanelMotion.preview = nil }
    }

    private static func at(_ delay: Double, _ f: @escaping () -> Void) {
        let w = DispatchWorkItem(block: f)
        work.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }
}
