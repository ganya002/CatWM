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
    var allowAccessibility: () -> Void = {}
    var allowInputMonitoring: () -> Void = {}
    var allowLogin: () -> Void = {}
    var skip: () -> Void = {}
    var learn: () -> Void = {}
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                AppGlyph(size: 64)
                Text("Welcome to Ouch").font(Theme.display(30)).foregroundStyle(ink).padding(.top, 6)
                Text("Ouch needs a little access before it can tile. Each button opens System Settings with a guide beside it.")
                    .font(Theme.body(13)).foregroundStyle(Color.black.opacity(0.5))
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                permission(granted: model.accessibility, symbol: "lock.fill",
                           tint: [Color(red: 1, green: 0.667, blue: 0.2), Color(red: 1, green: 0.55, blue: 0)],
                           title: "Accessibility", required: true,
                           detail: "macOS only lets apps move other apps' windows with this permission. It also lets your shortcuts work.",
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
                           detail: "Starts Ouch with your Mac. macOS asks you to allow it in Login Items.",
                           primary: false, action: model.allowLogin)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.06)))
            HStack(spacing: 8) {
                Text("Change these later in Settings → Overview.").font(Theme.body(11)).foregroundStyle(Color.black.opacity(0.5))
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
                .overlay(Image(systemName: granted ? "checkmark" : symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
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

/// The app's mark: a blue tile with a three-column window glyph.
struct AppGlyph: View {
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.234, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.55, blue: 1), Color(red: 0, green: 0.384, blue: 0.878)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "rectangle.split.3x1").font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white))
            .shadow(color: Color(red: 0, green: 0.384, blue: 0.878).opacity(0.35), radius: 7, y: 4)
    }
}

// MARK: - Intro wordmark

final class WordmarkModel: ObservableObject {
    @Published var subtitle = false
}

struct WordmarkView: View {
    @ObservedObject var model: WordmarkModel
    let size: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            Text("Ouch").font(Theme.wordmark(size)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            tagline(max(16, min(20, size / 7)))
                .foregroundStyle(Color.white.opacity(0.88))
                .opacity(model.subtitle ? 1 : 0)
                .animation(.easeOut(duration: 0.9), value: model.subtitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "*Wonderful* hyprland inspired tile manager for macOS." The bundled Roboto has no italic, so
    /// that word uses the system italic; "hyprland" is in Hyprland's blue.
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
            Text(model.title).font(Theme.display(27)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
            Text(model.text).font(Theme.body(13.5)).lineSpacing(3).foregroundStyle(Color.black.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if !model.caps.isEmpty {
                HStack(spacing: 10) {
                    Button(action: model.tryKeys) {
                        HStack(spacing: 6) { ForEach(Array(model.caps.enumerated()), id: \.offset) { _, c in keycap(c) } }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Click to try it")
                    if model.done {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                            Text("Nice").font(Theme.body(13, .semibold)).foregroundStyle(okGreen)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .padding(.top, 2)
                Text(model.hint).font(Theme.body(11)).foregroundStyle(Color.black.opacity(0.42))
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
                        GridRow {
                            Keycaps(caps: row.caps)
                            Text(row.label).font(Theme.body(12)).foregroundStyle(Color.black.opacity(0.7))
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
