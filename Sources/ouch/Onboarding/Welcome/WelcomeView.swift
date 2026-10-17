import AppKit
import SwiftUI

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let margin: CGFloat = 44
    static let width: CGFloat = 480 - 64

    var body: some View {
        ZStack(alignment: .topLeading) {
            permissions
                .opacity(model.page == .permissions ? 1 : 0)
                .offset(x: model.page == .permissions || reduceMotion ? 0 : -24)
                .allowsHitTesting(model.page == .permissions)
                .accessibilityHidden(model.page != .permissions)
            keys
                .opacity(model.page == .keys ? 1 : 0)
                .offset(x: model.page == .keys || reduceMotion ? 0 : 24)
                .allowsHitTesting(model.page == .keys)
                .accessibilityHidden(model.page != .keys)
        }
        .animation(Motion.snap(reduceMotion), value: model.page)
        .frame(width: Self.width)
        .surface(.xl)
        .padding(Self.margin)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                .offset(y: model.landed || reduceMotion ? 0 : -28)
                .opacity(model.landed ? 1 : 0)
                .animation(.easeIn(duration: 0.22), value: model.landed) // style-ok: the drop lands on the squish's beat
                .squish(on: model.landed, delay: 0.22)
                .padding(.leading, -6).padding(.vertical, -6)
            Text("Welcome to Ouch").textStyle(.largeTitle).oneLine()
                .padding(.top, 16).padding(.bottom, 8)
            Text("Each button opens System Settings, with steps beside it.")
                .font(Theme.body(13.5)).lineSpacing(2).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            OGroup {
                permission(granted: model.accessibility, symbol: "lock", title: "Accessibility", required: true,
                           detail: "Moves windows, reads shortcuts", primary: true, action: model.allowAccessibility)
                permission(granted: model.inputMonitoring, symbol: "keyboard", title: "Input Monitoring", required: false,
                           detail: "Makes Caps Lock shortcuts instant", primary: false, action: model.allowInputMonitoring)
                permission(granted: model.login, symbol: "power", title: "Open at login", required: false,
                           detail: "Starts Ouch when you log in", primary: false, action: model.allowLogin)
            }
            Spacer(minLength: 24)
            HStack(spacing: 8) {
                dots(0)
                Spacer(minLength: 0)
                OButton("Skip setup", variant: .ghost, action: model.skip)
                OButton("Continue", variant: .primary, size: .lg, shortcut: ["↩"], action: model.next)
                    .disabled(!model.accessibility)
                    .tooltip(model.accessibility ? "" : "Allow Accessibility first")
                    .keyboardShortcut(model.page == .permissions ? .defaultAction : nil)
            }
        }
    }

    private func permission(granted: Bool, symbol: String, title: String, required: Bool,
                            detail: String, primary: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted && symbol == "lock" ? "lock.open" : symbol)
                .font(Theme.symbol(Theme.Icon.lg))
                .foregroundStyle(Theme.accentInk)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).font(Theme.body(14)).oneLine()
                    Text(required ? "Required" : "Optional").font(Theme.body(11.5, .medium))
                        .foregroundStyle(required ? Theme.accentInk : Theme.inkMuted).oneLine()
                }
                Text(detail).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            }
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                if granted {
                    OStatus(kind: .success, text: symbol == "power" ? "On" : "Granted")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    OButton("Allow…", variant: primary ? .primary : .secondary, size: .sm, action: action)
                }
            }
        }
        .frame(minHeight: 52)
        .animation(Motion.easeOut, value: granted)
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ouch shortcut guide").textStyle(.largeTitle).oneLine()
                .padding(.top, 2).padding(.bottom, 8)
            Text("Like Vim, Photoshop or Blender, it takes some time to learn. Then you work faster.")
                .font(Theme.body(13.5)).lineSpacing(2).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)
            HStack(spacing: 12) {
                ForEach(KeyStyle.allCases, id: \.self) { s in
                    KeyStyleTile(style: s, selected: model.style == s) {
                        withAnimation(Motion.snap(reduceMotion)) { model.style = s }
                    }
                }
            }
            Spacer(minLength: 24)
            HStack(spacing: 8) {
                dots(1)
                Spacer(minLength: 0)
                OButton("Skip", variant: .ghost, action: model.skip)
                OButton("Learn", variant: .primary, size: .lg, shortcut: ["↩"], action: model.start)
                    .keyboardShortcut(model.page == .keys ? .defaultAction : nil)
            }
        }
    }

    private func dots(_ current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(i == current ? Theme.accent : Theme.inkFaint.opacity(0.45))
                    .frame(width: i == current ? 16 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of 2")
    }
}
