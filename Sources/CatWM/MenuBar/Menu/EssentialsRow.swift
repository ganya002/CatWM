import AppKit
import SwiftUI

struct EssentialsRow: View {
    @ObservedObject var model: MenuModel
    let enabled: Bool

    var body: some View {
        let manager = WindowManager.shared
        let focused = manager.focusedWindowState()
        let keys = ShortcutIndex()
        HStack(spacing: 4) {
            EssentialTile(title: "Tiling", label: "Tiling", symbol: "rectangle.split.3x1",
                          offSymbol: "rectangle.on.rectangle",
                          isOn: manager.tilingEnabled, shortcut: keys.keys("toggletiling")) {
                act { manager.toggleTiling() }
            }
            EssentialTile(title: "Float", label: "Float window", symbol: "macwindow.on.rectangle",
                          offSymbol: "macwindow",
                          isOn: focused?.floating == true,
                          shortcut: keys.keys("togglefloating")) {
                act { manager.dispatch("togglefloating", "") }
            }
                .disabled(focused == nil)
            EssentialTile(title: "Fullscreen", label: "Fullscreen", symbol: "arrow.down.right.and.arrow.up.left",
                          offSymbol: "arrow.up.left.and.arrow.down.right", isOn: focused?.fullscreen == true,
                          shortcut: keys.keys("fullscreen")) { act { manager.dispatch("fullscreen", "") } }
                .disabled(focused == nil)
            EssentialTile(title: "Retile", label: "Retile windows", symbol: "arrow.triangle.2.circlepath",
                          toggles: false, shortcut: keys.keys("retile"), rotates: true) {
                act { manager.dispatch("retile", "") }
            }
        }
        .padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 6)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func act(_ perform: () -> Void) {
        perform()
        model.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.refresh() }
    }
}
