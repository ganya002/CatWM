import AppKit
import SwiftUI

struct EssentialsRow: View {
    @ObservedObject var model: MenuModel
    let enabled: Bool

    var body: some View {
        let wm = WindowManager.shared
        let f = wm.focusedWindowState()
        let keys = ShortcutIndex()
        HStack(spacing: 4) {
            EssentialTile(title: "Tiling", label: "Tiling", symbol: "rectangle.split.3x1", offSymbol: "rectangle.on.rectangle",
                          isOn: wm.tilingEnabled, shortcut: keys.keys("toggletiling")) { act { wm.toggleTiling() } }
            EssentialTile(title: "Float", label: "Float window", symbol: "macwindow.on.rectangle", offSymbol: "macwindow",
                          isOn: f?.floating == true,
                          shortcut: keys.keys("togglefloating")) { act { wm.dispatch("togglefloating", "") } }
                .disabled(f == nil)
            EssentialTile(title: "Fullscreen", label: "Fullscreen", symbol: "arrow.down.right.and.arrow.up.left",
                          offSymbol: "arrow.up.left.and.arrow.down.right", isOn: f?.fullscreen == true,
                          shortcut: keys.keys("fullscreen")) { act { wm.dispatch("fullscreen", "") } }
                .disabled(f == nil)
            EssentialTile(title: "Retile", label: "Retile windows", symbol: "arrow.triangle.2.circlepath", shortcut: keys.keys("retile"), rotates: true) {
                act { wm.dispatch("retile", "") }
            }
        }
        .padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 6)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func act(_ f: () -> Void) {
        f()
        model.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.refresh() }
    }
}
