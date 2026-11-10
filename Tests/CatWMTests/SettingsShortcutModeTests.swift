@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@MainActor
struct SettingsShortcutModeTests {
    @Test func staleModeFallsBackToGlobal() {
        let doc = ConfigDocument(text: "$mod = ALT\nbind = $mod, h, movefocus, l\n")
        #expect(SettingsUI.shortcutMode("window", in: doc).isEmpty)
        #expect(SettingsUI.shortcutMode("", in: doc).isEmpty)
    }

    @Test func knownModeIsKept() {
        let doc = ConfigDocument(text: """
        $mod = ALT
        bind = $mod, w, submap, window
        submap = window
        bind = , h, movefocus, l
        submap = reset

        """)
        #expect(doc.submaps.contains("window"))
        #expect(SettingsUI.shortcutMode("window", in: doc) == "window")
    }
}
