import AppKit
import SwiftUI

// SwiftUI content for the onboarding overlays. Each one is hosted in its own borderless panel
// (see Onboarding.swift); none of them is a regular window.

private let blue = Color(red: 0, green: 122 / 255, blue: 1)
private let blueDown = Color(red: 0, green: 98 / 255, blue: 204 / 255)
private let okGreen = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255)
private let ink = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)

/// Hover state; @State can't be used here (its macro plugin isn't available to SwiftPM builds).
private final class Hover: ObservableObject { @Published var on = false }

/// Rounded pill button from the design: filled blue, or white with a hairline.
private struct Pill: View {
    let title: String
    var primary = false
    var enabled = true
    var height: CGFloat = 24
    var weight: Font.Weight = .regular
    let action: () -> Void
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.body(13, weight))
                .foregroundStyle(primary ? Color.white : ink)
                .padding(.horizontal, height > 26 ? 18 : 13)
                .frame(height: height)
                .background(Capsule().fill(primary ? (hover.on && enabled ? blueDown : blue).opacity(enabled ? 1 : 0.45)
                                                   : Color(white: hover.on ? 0.96 : 1)))
                .overlay(Capsule().strokeBorder(Color.black.opacity(primary ? 0 : 0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(primary ? 0.1 : 0.12), radius: 0.75, y: 0.5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}

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

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                    .offset(y: model.landed || reduceMotion ? 0 : -28)
                    .opacity(model.landed ? 1 : 0)
                    .animation(.easeIn(duration: 0.22), value: model.landed)
                    .squish(on: model.landed, delay: 0.22)
                    .overlay(alignment: .topLeading) {
                        ImpactBurst(trigger: model.landed, size: 26, delay: 0.22).offset(x: -6, y: 0)
                    }
                    .padding(.vertical, -10) // the icon artwork has its own transparent margin
                Text("Welcome to Ouch").font(Theme.display(30)).foregroundStyle(ink).padding(.top, 6)
                Text("Ouch needs a few permissions to tile. Each button opens System Settings with a guide beside it.")
                    .font(Theme.body(13)).foregroundStyle(Color.black.opacity(0.5))
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                permission(granted: model.accessibility, symbol: "lock.fill",
                           tint: [Color(red: 1, green: 0.667, blue: 0.2), Color(red: 1, green: 0.55, blue: 0)],
                           title: "Accessibility", required: true,
                           detail: "Lets Ouch move other apps' windows and respond to your shortcuts.",
                           primary: true, action: model.allowAccessibility)
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1).padding(.leading, 58).padding(.trailing, 14)
                permission(granted: model.inputMonitoring, symbol: "keyboard",
                           tint: [Color(red: 0.2, green: 0.78, blue: 0.9), Color(red: 0.1, green: 0.55, blue: 0.85)],
                           title: "Input Monitoring", required: false,
                           detail: "Makes shortcuts that use Caps Lock instant instead of needing a hold.",
                           primary: false, action: model.allowInputMonitoring)
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1).padding(.leading, 58).padding(.trailing, 14)
                permission(granted: model.login, symbol: "power",
                           tint: [Color(red: 0.486, green: 0.478, blue: 0.918), Color(red: 0.345, green: 0.337, blue: 0.839)],
                           title: "Open at login", required: false,
                           detail: "Starts Ouch when you log in. macOS may ask you to allow it in Login Items.",
                           primary: false, action: model.allowLogin)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.06)))
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Pill(title: "Skip tutorial", action: model.skip)
                Pill(title: "Learn the shortcuts", primary: true, enabled: model.accessibility, action: model.learn)
                    .help(model.accessibility ? "" : "Allow Accessibility first")
            }
        }
        .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 22)
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.984)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5))
        .environment(\.colorScheme, .light)
    }

    private func permission(granted: Bool, symbol: String, tint: [Color], title: String, required: Bool,
                            detail: String, primary: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: granted ? [Color(red: 0.3, green: 0.85, blue: 0.39), Color(red: 0.18, green: 0.7, blue: 0.31)] : tint,
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: granted ? "checkmark" : symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace)).symbolEffect(.bounce, value: granted))
                .overlay(alignment: .topLeading) {
                    ImpactBurst(trigger: granted, size: 18).offset(x: -9, y: -9).opacity(granted ? 1 : 0)
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(Theme.body(13, .medium)).foregroundStyle(ink)
                    Text(required ? "Required" : "Optional").font(Theme.body(10, .semibold))
                        .foregroundStyle(required ? Color(red: 0.79, green: 0.2, blue: 0) : Color.black.opacity(0.55))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(required ? Color.orange.opacity(0.16) : Color.black.opacity(0.06)))
                }
                Text(detail).font(Theme.body(11)).foregroundStyle(Color.black.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if granted {
                Text("Allowed").font(Theme.body(12, .medium)).foregroundStyle(okGreen)
            } else {
                Pill(title: "Allow…", primary: primary, action: action)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .animation(.easeOut(duration: 0.3), value: granted)
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
            Text("Ouch").font(Theme.display(size)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .squish(on: model.landed, delay: 0.75)
                .overlay(alignment: .topLeading) {
                    ImpactBurst(trigger: model.landed, size: size * 0.45, delay: 0.75).offset(x: -size * 0.3, y: -size * 0.15)
                }
            tagline(max(16, min(20, size / 7)))
                .foregroundStyle(Color.white.opacity(0.88))
                .opacity(model.subtitle ? 1 : 0)
                .animation(.easeOut(duration: 0.9), value: model.subtitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "*Wonderful* hyprland inspired tile manager for macOS." "Wonderful" is set in the system italic;
    /// "hyprland" is in Hyprland's blue.
    private func tagline(_ pt: CGFloat) -> Text {
        Text("Wonderful").font(.system(size: pt).italic())
            + Text(" ").font(Theme.body(pt))
            + Text("hyprland").font(Theme.body(pt, .medium)).foregroundColor(hyprlandBlue)
            + Text(" inspired tile manager for macOS.").font(Theme.body(pt))
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

struct CoachCardView: View {
    @ObservedObject var model: CoachModel
    static let width: CGFloat = 360
    private let surface = Color(white: 1, opacity: 0.96)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.kicker.uppercased()).font(Theme.mono(11, .bold)).tracking(0.66)
                    .foregroundStyle(model.final ? okGreen : blue)
                Spacer()
                if model.canSkip {
                    SkipLink(action: model.skip)
                }
            }
            Text(model.title).font(Theme.heading(27)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
            Text(model.text).font(Theme.body(13.5)).lineSpacing(3).foregroundStyle(Color.black.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if !model.caps.isEmpty {
                HStack(spacing: 10) {
                    Button(action: model.tryKeys) {
                        HStack(spacing: 6) { ForEach(Array(model.caps.enumerated()), id: \.offset) { _, c in keycap(c) } }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if model.done {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                                .transition(.symbolEffect(.appear))
                                .overlay(alignment: .topLeading) {
                                    ImpactBurst(trigger: model.done, size: 14, delay: 0.05).offset(x: -8, y: -8)
                                }
                            Text("Nice").font(Theme.body(13, .semibold)).foregroundStyle(okGreen)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .padding(.top, 2)
            }
            if let warning = model.warning {
                Text(warning).font(Theme.body(12)).foregroundStyle(Color(red: 0.79, green: 0.2, blue: 0))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.final {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        if row.caps.isEmpty { // a section heading
                            Text(row.label.uppercased()).font(Theme.mono(10, .bold)).tracking(0.6)
                                .foregroundStyle(Color.black.opacity(0.45))
                                .padding(.top, 6)
                                .gridCellColumns(2)
                        } else {
                            GridRow {
                                Keycaps(caps: row.caps)
                                Text(row.label).font(Theme.body(12)).foregroundStyle(Color.black.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if let button = model.button {
                HStack {
                    Spacer()
                    Pill(title: button, primary: true, height: 32, weight: .semibold, action: model.next)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.07))
                    Capsule().fill(blue).frame(width: g.size.width * model.progress)
                }
            }
            .frame(height: 3)
            .animation(.spring(response: 0.5, dampingFraction: 0.9), value: model.progress)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 18)
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
        .background(alignment: caretAlignment) { caret }
        .shadow(color: .black.opacity(0.3), radius: 22, y: 14)
        // Room for the caret and the shadow; the panel is transparent there, so clicks pass through.
        .padding(.vertical, 10).padding(.horizontal, 24).padding(.bottom, 20)
        .environment(\.colorScheme, .light)
        .animation(.easeOut(duration: 0.2), value: model.done)
    }

    private var caretAlignment: Alignment {
        if case .down = model.caret { return .bottom }
        return .topLeading
    }

    @ViewBuilder private var caret: some View {
        let diamond = RoundedRectangle(cornerRadius: 3).fill(surface).frame(width: 14, height: 14).rotationEffect(.degrees(45))
        switch model.caret {
        case .none: EmptyView()
        case .up(let x): diamond.offset(x: x - 7, y: -6)
        case .down: diamond.offset(y: 6)
        }
    }

    private func keycap(_ label: String) -> some View {
        let on = model.pressed
        return Text(label)
            .font(Theme.body(label.count > 2 ? 13 : 15, .medium))
            .foregroundStyle(on ? Color.white : ink)
            .padding(.horizontal, label.count > 2 ? 12 : 10)
            .frame(minWidth: 34, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? blue : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? blueDown : Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3)))
            .shadow(color: on ? blue.opacity(0.35) : .black.opacity(0.12), radius: on ? 4 : 0, y: on ? 0 : 2)
            .offset(y: on ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: on)
    }
}

private struct SkipLink: View {
    let action: () -> Void
    @StateObject private var hover = Hover()
    var body: some View {
        Button(action: action) {
            Text("Skip tutorial").font(Theme.body(12))
                .foregroundStyle(hover.on ? ink : Color.black.opacity(0.5))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(hover.on ? 0.06 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}

// MARK: - Menu bar tip

struct MenuBarTipView: View {
    @ObservedObject var model: MenuBarTipModel
    private let surface = Color(white: 1, opacity: 0.96)

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: model.state == .good ? "checkmark.circle.fill" : "menubar.arrow.up.rectangle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.state == .good ? okGreen : blue)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.body(12, .semibold)).foregroundStyle(ink)
                if let detail {
                    Text(detail).font(Theme.body(11.5)).lineSpacing(1.5).foregroundStyle(Color.black.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(width: model.state == .good ? nil : 252, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.13), lineWidth: 0.5))
        .background(alignment: .topLeading) {
            if let x = model.caret {
                RoundedRectangle(cornerRadius: 2).fill(surface).frame(width: 10, height: 10)
                    .rotationEffect(.degrees(45)).offset(x: x - 14 - 5, y: -4)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        // Room for the caret and the shadow; the panel ignores the mouse anyway.
        .padding(.top, 8).padding(.horizontal, 14).padding(.bottom, 16)
        .fixedSize()
        .environment(\.colorScheme, .light)
    }

    private var title: String {
        switch model.state {
        case .move: "Keep Ouch in reach"
        case .good: "Good spot for Ouch"
        case .hidden: "Ouch is hidden by the notch"
        }
    }

    private var detail: String? {
        switch model.state {
        case .good: nil
        case .move: "Icons further left are hidden first when the menu bar fills up. Open Control Center, click Edit Controls and drag this one to the right."
        case .hidden: "Open Control Center, click Edit Controls and drag Ouch to the right, near the clock."
        }
    }
}
