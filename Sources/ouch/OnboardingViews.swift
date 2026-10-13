import AppKit
import SwiftUI

// SwiftUI content for the onboarding overlays. Each one is hosted in its own borderless panel
// (see Onboarding.swift); none of them is a regular window. All of them are Surfaces: the welcome
// card at `xl`, tour steps at `lg` in the accent tone, the menu bar tip at `md`.

// MARK: - Welcome card

final class WelcomeModel: ObservableObject {
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var login = false
    /// Set once the card is on screen; the icon drops in and lands.
    @Published var landed = false
    var allowAccessibility: () -> Void = {}
    var allowInputMonitoring: () -> Void = {}
    var allowLogin: () -> Void = {}
    var skip: () -> Void = {}
    var learn: () -> Void = {}
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Transparent room around the card for its shadow.
    static let margin: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                .offset(y: model.landed || reduceMotion ? 0 : -28)
                .opacity(model.landed ? 1 : 0)
                .animation(.easeIn(duration: 0.22), value: model.landed)
                .squish(on: model.landed, delay: 0.22)
                .overlay(alignment: .topLeading) {
                    ImpactBurst(trigger: model.landed, size: 24, delay: 0.22).offset(x: -8, y: -4)
                }
                .padding(.leading, -6).padding(.vertical, -6) // the icon artwork has its own transparent margin
            Text("Welcome to Ouch").font(Theme.display(40)).tracking(-1).oneLine()
                .padding(.top, 16).padding(.bottom, 8)
            Text("Ouch needs a few permissions to tile. Each button opens System Settings with a guide beside it.")
                .font(Theme.body(13.5)).lineSpacing(2).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            OGroup {
                permission(granted: model.accessibility, symbol: "lock", title: "Accessibility", required: true,
                           detail: "Moves windows and hears your shortcuts", primary: true, action: model.allowAccessibility)
                permission(granted: model.inputMonitoring, symbol: "keyboard", title: "Input Monitoring", required: false,
                           detail: "Makes Caps Lock shortcuts instant", primary: false, action: model.allowInputMonitoring)
                permission(granted: model.login, symbol: "power", title: "Open at login", required: false,
                           detail: "Starts Ouch when you log in", primary: false, action: model.allowLogin)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                OButton("Skip tutorial", variant: .ghost, action: model.skip)
                OButton("Take the tour", variant: .primary, size: .lg, shortcut: ["↩"], action: model.learn)
                    .disabled(!model.accessibility)
                    .help(model.accessibility ? "" : "Allow Accessibility first")
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 24)
        }
        .frame(width: 480 - 64)
        .surface(.xl)
        .padding(Self.margin)
    }

    private func permission(granted: Bool, symbol: String, title: String, required: Bool,
                            detail: String, primary: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(granted ? Theme.success : Theme.accentInk)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22)
                .overlay(alignment: .topLeading) {
                    ImpactBurst(trigger: granted, size: 18).offset(x: -9, y: -9).opacity(granted ? 1 : 0)
                }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).font(Theme.body(14)).oneLine()
                    Text(required ? "Required" : "Optional").font(Theme.body(11.5, .medium))
                        .foregroundStyle(required ? Theme.accentInk : Theme.inkMuted).oneLine()
                }
                Text(detail).font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
            }
            Spacer(minLength: 0)
            if granted {
                OStatus(kind: .success, text: "Granted").transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                OButton("Allow…", variant: primary ? .primary : .secondary, size: .sm, action: action)
            }
        }
        .frame(minHeight: 52)
        .animation(Motion.easeOut, value: granted)
    }
}

// MARK: - Intro wordmark

final class WordmarkModel: ObservableObject {
    @Published var subtitle = false
    /// Flipped when the wordmark arrives; it lands with a bump.
    @Published var landed = false
}

struct WordmarkView: View {
    @ObservedObject var model: WordmarkModel
    let size: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            Text("Ouch").font(Theme.wordmark(size)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .squish(on: model.landed, delay: 0.75)
                .overlay(alignment: .topLeading) {
                    ImpactBurst(trigger: model.landed, size: size * 0.45, delay: 0.75).offset(x: -size * 0.3, y: -size * 0.15)
                }
            tagline(max(16, min(22, size / 6)))
                .foregroundStyle(Color.white.opacity(0.88))
                .opacity(model.subtitle ? 1 : 0)
                .animation(.easeOut(duration: 0.9), value: model.subtitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Wonderful *hyprland* inspired tile manager for macOS.", light, with "hyprland" at 500 in Hyprland's blue.
    private func tagline(_ pt: CGFloat) -> Text {
        Text("Wonderful ").font(Theme.body(pt, .light))
            + Text("hyprland").font(Theme.body(pt, .medium)).foregroundColor(hyprlandBlue)
            + Text(" inspired tile manager for macOS.").font(Theme.body(pt, .light))
    }
}

/// Hyprland's accent (its default active border, #33CCFF).
private let hyprlandBlue = Color(red: 0x33 / 255, green: 0xCC / 255, blue: 1)

// MARK: - Coach card

final class CoachModel: ObservableObject {
    enum Caret: Equatable { case none, up(CGFloat), down }
    @Published var kicker = ""
    @Published var title = ""
    @Published var text = ""
    @Published var caps: [String] = []
    @Published var hint = ""
    @Published var pressed = false
    @Published var done = false
    @Published var warning: String?
    @Published var button: String?
    @Published var final = false
    @Published var canSkip = true
    @Published var rows: [(caps: [String], label: String)] = []
    @Published var progress: Double = 0
    @Published var caret: Caret = .none
    var tryKeys: () -> Void = {}
    var next: () -> Void = {}
    var skip: () -> Void = {}
}

/// One step of the keyboard tour: Surface `lg` filled with `accent`, pointing at the real target.
struct CoachCardView: View {
    @ObservedObject var model: CoachModel
    static let width: CGFloat = 344
    /// Transparent room around the card for its caret and shadow; the panel lets clicks through there.
    static let inset = EdgeInsets(top: 12, leading: 28, bottom: 36, trailing: 28)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // head: lead symbol, kicker, close
            HStack(spacing: 8) {
                Image(systemName: model.final ? "checkmark.circle.fill" : "keyboard")
                    .font(.system(size: 13, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text(model.kicker).kicker(Theme.onAccent).oneLine()
                Spacer(minLength: 8)
                if model.canSkip {
                    OButton("Skip tour", variant: .ghost, size: .sm, onAccent: true, action: model.skip)
                        .padding(.trailing, -8)
                }
            }
            .frame(minHeight: 22)
            Text(model.title).font(Theme.body(22)).tracking(-0.2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.bottom, 4)
            Text(model.text).font(Theme.body(13.5)).lineSpacing(2).opacity(0.86)
                .fixedSize(horizontal: false, vertical: true)
            if !model.caps.isEmpty {
                HStack(spacing: 12) {
                    Button(action: model.tryKeys) {
                        Kbd(keys: model.caps, large: true, pressed: model.pressed, onAccent: true).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model.hint)
                    if model.done {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .transition(.symbolEffect(.appear))
                                .overlay(alignment: .topLeading) {
                                    ImpactBurst(trigger: model.done, size: 14, delay: 0.05).offset(x: -8, y: -8)
                                }
                            Text("Nice").font(Theme.body(13.5, .medium))
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "cursorarrow.rays")
                            Text("Press it now").font(Theme.body(13))
                        }
                        .opacity(0.8)
                    }
                }
                .padding(.top, 16)
            }
            if let warning = model.warning {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(warning).font(Theme.body(12.5)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.onAccent.opacity(0.16)))
                .padding(.top, 14)
            }
            if model.final {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        if row.caps.isEmpty { // a section heading
                            Text(row.label).kicker(Theme.onAccent).opacity(0.75)
                                .padding(.top, 6)
                                .gridCellColumns(2)
                        } else {
                            GridRow {
                                HStack(spacing: 2) {
                                    ForEach(Array(row.caps.enumerated()), id: \.offset) { _, c in
                                        Text(c).font(Theme.keys(11.5, .medium)).oneLine()
                                            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                                            .background(RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(Theme.onAccent.opacity(0.18)))
                                    }
                                }
                                Text(row.label).font(Theme.body(12.5)).oneLine()
                            }
                        }
                    }
                }
                .padding(.top, 14)
            }
            if let button = model.button {
                HStack {
                    Spacer()
                    OButton(button, variant: .primary, shortcut: ["↩"], onAccent: true, action: model.next)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 20)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.onAccent.opacity(0.25))
                    Capsule().fill(Theme.onAccent).frame(width: g.size.width * model.progress)
                }
            }
            .frame(height: 3)
            .padding(.top, 14)
            .animation(Motion.spring, value: model.progress)
        }
        .frame(width: Self.width - 40)
        .surface(.lg, tone: .accent, caret: caret)
        .padding(Self.inset)
        .animation(.easeOut(duration: 0.2), value: model.done)
    }

    private var caret: Caret {
        switch model.caret {
        case .none: .none
        case .up(let x): .top(x)
        case .down: .bottom
        }
    }
}

// MARK: - Menu bar tip

/// Hangs under the menu bar item during onboarding: a Surface `md` with a caret pointing at the item.
struct MenuBarTipView: View {
    @ObservedObject var model: MenuBarTipModel
    /// Transparent room for the caret and shadow; the panel ignores the mouse anyway.
    static let inset = EdgeInsets(top: 10, leading: 20, bottom: 28, trailing: 20)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: model.state == .good ? "checkmark.circle.fill" : "lightbulb")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.state == .good ? Theme.success : Theme.accentInk)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.heading()).oneLine()
                if let detail {
                    Text(detail).font(Theme.body(12.5)).lineSpacing(1.5).foregroundStyle(Theme.inkMuted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(width: model.state == .good ? nil : 288, alignment: .leading)
        .surface(.md, caret: model.caret.map { .top($0 - Self.inset.leading) } ?? .none)
        .padding(Self.inset)
        .fixedSize()
    }

    private var title: String {
        switch model.state {
        case .move: "Keep Ouch in reach"
        case .good: "Good spot for Ouch"
        case .hidden: "Ouch is behind the notch"
        }
    }

    private var detail: String? {
        switch model.state {
        case .good: nil
        case .move: "Items further left hide first. Drag Ouch right in Control Center › Edit Controls."
        case .hidden: "Drag Ouch right, near the clock, in Control Center › Edit Controls."
        }
    }
}
