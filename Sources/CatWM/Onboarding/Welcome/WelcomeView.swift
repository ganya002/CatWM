import AppKit
import CatWMKit
import SwiftUI

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static var margin: CGFloat { Elevation.float.room }
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
        .surface(.extraLarge)
        .padding(Self.margin)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            CatMascot(feeling: .content).frame(height: 72).foregroundStyle(Theme.ink)
                .offset(y: model.landed || reduceMotion ? 0 : -28)
                .opacity(model.landed ? 1 : 0)
                .animation(Motion.drop, value: model.landed)
                .squish(on: model.landed, delay: 0.22)
                .padding(.top, 4)
            Text("Welcome to CatWM").textStyle(.largeTitle).oneLine()
                .padding(.top, 16).padding(.bottom, 8)
            Text("Each button opens System Settings, with steps beside it.")
                .font(Theme.body()).lineSpacing(2).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            OGroup {
                permission(PermissionItem(granted: model.accessibility, symbol: "lock", title: "Accessibility",
                                          required: true, detail: "Moves windows, reads shortcuts", primary: true,
                                          action: model.allowAccessibility))
                permission(PermissionItem(granted: model.inputMonitoring, symbol: "keyboard", title: "Input Monitoring",
                                          required: false, detail: "Makes Caps Lock shortcuts instant", primary: false,
                                          action: model.allowInputMonitoring))
                permission(PermissionItem(granted: model.screenRecording, symbol: "record.circle",
                                          title: "Screen Recording", required: false,
                                          detail: "Takes a picture of each saved template", primary: false,
                                          action: model.allowScreenRecording,
                                          test: model.screenTestDone ? nil : model.takeTestImage))
                permission(PermissionItem(granted: model.fullDiskAccess, symbol: "bell.badge",
                                          title: "Full Disk Access", required: false,
                                          detail: "Puts each notification on the right tab", primary: false,
                                          action: model.allowFullDiskAccess))
                permission(PermissionItem(granted: model.login, symbol: "power", title: "Open at login",
                                          required: false, detail: "Starts CatWM when you log in", primary: false,
                                          action: model.allowLogin))
            }
            Spacer(minLength: 24)
            HStack(spacing: 8) {
                dots(0)
                Spacer(minLength: 0)
                OButton("Skip setup", variant: .ghost, action: model.skip)
                OButton("Continue", variant: .primary, size: .large, shortcut: ["↩"], action: model.next)
                    .disabled(!model.accessibility)
                    .keyboardShortcut(model.page == .permissions ? .defaultAction : nil)
            }
        }
    }

    private struct PermissionItem {
        let granted: Bool
        let symbol: String
        let title: String
        let required: Bool
        let detail: String
        let primary: Bool
        let action: () -> Void
        var test: (() -> Void)?
    }

    private func permission(_ item: PermissionItem) -> some View {
        let granted = item.granted, symbol = item.symbol, required = item.required
        return HStack(spacing: 12) {
            Image(systemName: granted && symbol == "lock" ? "lock.open" : symbol)
                .font(Theme.symbol(Theme.Icon.large))
                .foregroundStyle(Theme.inkMuted)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title).font(Theme.body()).oneLine()
                    Text(required ? "Required" : "Optional").font(TextStyle.caption.font.weight(.medium))
                        .foregroundStyle(required ? Theme.ink : Theme.inkMuted).oneLine()
                }
                Text(item.detail).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            }
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                if granted, let test = item.test {
                    OButton("Test Image", size: .small, action: test)
                } else if granted {
                    OStatus(kind: .success, text: symbol == "power" ? "On" : "Granted")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    OButton("Allow…", variant: item.primary ? .primary : .secondary, size: .small, action: item.action)
                }
            }
        }
        .frame(minHeight: 52)
        .animation(Motion.easeOut, value: granted)
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CatWM shortcut guide").textStyle(.largeTitle).oneLine()
                .padding(.top, 2).padding(.bottom, 8)
            Text("Like Vim, Photoshop or Blender, it takes some time to learn. Then you work faster.")
                .font(Theme.body()).lineSpacing(2).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Theme.Space.extraLarge)
            HStack(spacing: 12) {
                ForEach(KeyStyle.allCases, id: \.self) { style in
                    KeyStyleTile(style: style, selected: model.style == style) {
                        withAnimation(Motion.snap(reduceMotion)) { model.style = style }
                    }
                }
            }
            Spacer(minLength: 24)
            HStack(spacing: 8) {
                dots(1)
                Spacer(minLength: 0)
                OButton("Skip", variant: .ghost, action: model.skip)
                OButton("Learn", variant: .primary, size: .large, shortcut: ["↩"], action: model.start)
                    .keyboardShortcut(model.page == .keys ? .defaultAction : nil)
            }
        }
    }

    private func dots(_ current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(i == current ? Theme.ink : Theme.inkFaint.opacity(0.45))
                    .frame(width: i == current ? 16 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of 2")
    }
}

final class WelcomeModel: ObservableObject {
    enum Page { case permissions, keys }
    @Published var page = Page.permissions
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var screenRecording = false
    @Published var screenTestDone = false
    @Published var fullDiskAccess = false
    @Published var login = false
    @Published var style: KeyStyle?
    @Published var landed = false
    var allowAccessibility: () -> Void = {}
    var allowInputMonitoring: () -> Void = {}
    var allowScreenRecording: () -> Void = {}
    var allowFullDiskAccess: () -> Void = {}
    var takeTestImage: () -> Void = {}
    var allowLogin: () -> Void = {}
    var skip: () -> Void = {}
    var next: () -> Void = {}
    var start: () -> Void = {}
}
