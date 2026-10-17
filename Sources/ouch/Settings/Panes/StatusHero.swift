import AppKit
import SwiftUI

struct StatusHero: View {
    @ObservedObject var ui: SettingsUI

    var body: some View {
        let s = ui.status
        let live = s.trusted && s.keybindsActive && s.tilingEnabled
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                BadgedAppIcon(badge: !s.trusted ? "lock.circle.fill" : live ? "checkmark.circle.fill"
                                  : s.keybindsActive ? "pause.circle.fill" : "exclamationmark.circle.fill",
                              color: live ? Theme.success : Theme.warning, size: 52)
                    .squish(on: live, when: live)
                VStack(alignment: .leading, spacing: 3) {
                    Text(!s.trusted ? "Ouch needs Accessibility access" : !s.tilingEnabled ? "Tiling is paused"
                         : s.keybindsActive ? "Ouch is running" : "Keyboard shortcuts aren't active")
                        .textStyle(.title).oneLine()
                        .contentTransition(.opacity)
                    Text(s.trusted ? summary(s) : "macOS only lets apps move other apps' windows with this permission.")
                        .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                if s.trusted && !s.keybindsActive {
                    OButton("Retry", icon: "arrow.clockwise", size: .sm) { Hotkeys.shared.restart(); ui.refreshStatus() }
                }
            }
            if !s.trusted {
                VStack(alignment: .leading, spacing: 8) {
                    OStep(n: 1, text: "Click **Grant Access**. A guide appears next to System Settings.")
                    OStep(n: 2, text: "Turn on Ouch in the list.")
                    OStep(n: 3, text: "Still not working after a rebuild? Click **Reset Permission**, then turn it on again.")
                }
                HStack(spacing: 8) {
                    OButton("Grant Access", icon: "lock.open", variant: .primary) { Permissions.request() }
                    OButton("Reset Permission", variant: .ghost) { Permissions.reset() }
                    Spacer()
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    Text("Waiting…").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.easeOut, value: s.trusted)
    }

    private func summary(_ s: WindowManager.Status) -> String {
        let w = "\(s.tiled) tiled window\(s.tiled == 1 ? "" : "s")"
        let f = s.floating > 0 ? " · \(s.floating) floating" : ""
        let d = " · \(s.screens.count) display\(s.screens.count == 1 ? "" : "s")"
        return w + f + d
    }
}
