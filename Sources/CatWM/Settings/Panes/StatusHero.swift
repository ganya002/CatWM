import AppKit
import CatWMKit
import SwiftUI

struct StatusHero: View {
    @ObservedObject var settingsUI: SettingsUI

    var body: some View {
        let status = settingsUI.status
        let live = status.trusted && status.keybindsActive && status.tilingEnabled
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                BadgedAppIcon(badge: !status.trusted ? "lock.circle.fill" : live ? "checkmark.circle.fill"
                                  : status.keybindsActive ? "pause.circle.fill" : "exclamationmark.circle.fill",
                              color: live ? Theme.success : Theme.warning, size: 52)
                    .squish(on: live, when: live)
                VStack(alignment: .leading, spacing: Theme.Space.extraSmall) {
                    Text(!status.trusted ? "CatWM needs Accessibility access"
                         : !status.tilingEnabled ? "Tiling is paused"
                         : status.keybindsActive ? "CatWM is running" : "Keyboard shortcuts aren't active")
                        .textStyle(.title).oneLine()
                        .contentTransition(.opacity)
                    Text(status.trusted
                         ? summary(status)
                         : "macOS only lets apps move other apps' windows with this permission.")
                        .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                if status.trusted && !status.keybindsActive {
                    OButton("Retry", icon: "arrow.clockwise", size: .small) {
                        Hotkeys.shared.restart(); settingsUI.refreshStatus()
                    }
                }
            }
            if !status.trusted {
                VStack(alignment: .leading, spacing: 8) {
                    OStep(number: 1, text: "Click **Grant Access**. A guide appears next to System Settings.")
                    OStep(number: 2, text: "Turn on CatWM in the list.")
                    OStep(number: 3, text: "Still not working after a rebuild? "
                        + "Click **Reset Permission**, then turn it on again.")
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
        .animation(Motion.easeOut, value: status.trusted)
    }

    private func summary(_ status: WindowManager.Status) -> String {
        let windows = "\(status.tiled) tiled window\(status.tiled == 1 ? "" : "s")"
        let floating = status.floating > 0 ? " · \(status.floating) floating" : ""
        let displays = " · \(status.screens.count) display\(status.screens.count == 1 ? "" : "s")"
        return windows + floating + displays
    }
}
