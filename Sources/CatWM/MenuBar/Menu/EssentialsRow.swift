import AppKit
import CatWMKit
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
                          isOn: manager.tilingEnabled, shortcut: keys.keys(WindowActions.toggletiling.name)) {
                act { manager.toggleTiling() }
            }
            EssentialTile(title: "Float", label: "Float window", symbol: "macwindow.on.rectangle",
                          offSymbol: "macwindow",
                          isOn: focused?.floating == true,
                          shortcut: keys.keys(WindowActions.togglefloating.name)) {
                act { manager.dispatch(WindowActions.togglefloating.name, "") }
            }
                .disabled(focused == nil)
            EssentialTile(title: "Fullscreen", label: "Fullscreen", symbol: "arrow.down.right.and.arrow.up.left",
                          offSymbol: "arrow.up.left.and.arrow.down.right", isOn: focused?.fullscreen == true,
                          shortcut: keys.keys(WindowActions.fullscreen.name)) {
                act { manager.dispatch(WindowActions.fullscreen.name, "") }
            }
                .disabled(focused == nil)
            EssentialTile(title: "Retile", label: "Retile windows", symbol: "arrow.triangle.2.circlepath",
                          toggles: false, shortcut: keys.keys(WindowActions.retile.name), rotates: true) {
                act { manager.dispatch(WindowActions.retile.name, "") }
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
