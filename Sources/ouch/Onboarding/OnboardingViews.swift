// Onboarding: SwiftUI views for the onboarding overlays (welcome card, coach steps).
import AppKit
import SwiftUI

// SwiftUI content for the onboarding overlays. Each one is hosted in its own borderless panel
// (see Onboarding.swift); none of them is a regular window. All of them are Surfaces: the welcome
// card at `xl`, coach steps at `lg` in the accent tone, the menu bar tip at `md`.

// MARK: - Welcome card

/// The two built-in key sets the welcome card offers.
enum KeyStyle: String, CaseIterable {
    case vim, wasd

    var configID: String { ConfigLibrary.builtInPrefix + (self == .vim ? "keyboard.default" : "keyboard.wasd") }
    var title: String { self == .vim ? "Vim" : "WASD" }
    var caption: String { self == .vim ? "Right hand on the home row" : "Left hand, like a game" }

    /// The built-in set that's active now, if one is.
    static var current: KeyStyle? {
        let id = SettingsWindow.shared.library.current(.keyboard).id
        return allCases.first { $0.configID == id }
    }
}

final class WelcomeModel: ObservableObject {
    enum Page { case permissions, keys }
    @Published var page = Page.permissions
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var login = false
    @Published var style: KeyStyle?
    /// Set once the card is on screen; the icon drops in and lands.
    @Published var landed = false
    var allowAccessibility: () -> Void = {}
    var allowInputMonitoring: () -> Void = {}
    var allowLogin: () -> Void = {}
    var skip: () -> Void = {}
    var next: () -> Void = {}
    var start: () -> Void = {}
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Transparent room around the card for its shadow.
    static let margin: CGFloat = 44
    static let width: CGFloat = 480 - 64

    var body: some View {
        // Both pages are always laid out so the card keeps one size; the hidden one steps aside.
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

    // MARK: Permissions

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                .offset(y: model.landed || reduceMotion ? 0 : -28)
                .opacity(model.landed ? 1 : 0)
                .animation(.easeIn(duration: 0.22), value: model.landed) // style-ok: the drop lands on the squish's beat
                .squish(on: model.landed, delay: 0.22)
                .padding(.leading, -6).padding(.vertical, -6) // the icon artwork has its own transparent margin
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
                    .keyboardShortcut(model.page == .permissions ? .defaultAction : nil) // both pages stay laid out
            }
        }
    }

    private func permission(granted: Bool, symbol: String, title: String, required: Bool,
                            detail: String, primary: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            // The row's own symbol stays (a lock opens); the trailing status carries the check, so the
            // row doesn't show two of them.
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

    // MARK: Keys

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

    /// Where you are in the card: two small dots, the current one in accent.
    private func dots(_ current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(i == current ? Theme.accent : Theme.inkFaint.opacity(0.45)) // hairline vanished on raised dark
                    .frame(width: i == current ? 16 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of 2")
    }
}

/// One of the two key sets: its four direction keys drawn where they sit, the name, and a caption.
/// A control, so it gets a fill; the chosen one is `accent`.
private struct KeyStyleTile: View {
    let style: KeyStyle
    let selected: Bool
    let action: () -> Void
    @StateObject private var model = Model()

    final class Model: ObservableObject { @Published var hover = false }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                cluster.frame(maxWidth: .infinity).frame(height: 132)
                HStack(spacing: 6) {
                    Text(style.title).font(Theme.heading()).oneLine()
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(Theme.symbol(Theme.Icon.lg))
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.top, 12)
                Text(style.caption).textStyle(.caption).oneLine()
                    .foregroundStyle(selected ? Theme.onAccent.opacity(0.85) : Theme.inkMuted)
                    .padding(.top, 1)
            }
            .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(selected ? Theme.accent : model.hover ? Theme.wellHover : Theme.well))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.97))
        .onHover { model.hover = $0 }
        .animation(Motion.fadeMedium, value: selected)
        .accessibilityLabel("\(style.title): \(style.caption)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// H J K L in a row, or W over A S D.
    @ViewBuilder private var cluster: some View {
        switch style {
        case .vim:
            HStack(spacing: 5) { ForEach(["H", "J", "K", "L"], id: \.self) { cap($0) } }
        case .wasd:
            VStack(spacing: 5) {
                cap("W")
                HStack(spacing: 5) { ForEach(["A", "S", "D"], id: \.self) { cap($0) } }
            }
        }
    }

    private func cap(_ k: String) -> some View {
        Kbd(keys: [k], size: .medium, onAccent: selected)
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
                .legible()
                .squish(on: model.landed, delay: 0.3) // on the melody note
            tagline(max(16, min(22, size / 6)))
                .foregroundStyle(Color.white.opacity(0.92))
                .legible(strong: true) // reads over the tiles behind it
                .opacity(model.subtitle ? 1 : 0)
                .animation(.easeOut(duration: 0.9), value: model.subtitle) // style-ok: the intro's timing, set to the music
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "*Hyprland*-style tiling for macOS.", light, with "Hyprland" at 500 in Hyprland's blue.
    private func tagline(_ pt: CGFloat) -> Text {
        Text("Hyprland").font(Theme.body(pt, .medium)).foregroundColor(hyprlandBlue)
            + Text("-style tiling for macOS.").font(Theme.body(pt, .light))
    }
}

/// Hyprland's accent (its default active border, #33CCFF): Hyprland's own colour, not a token.
private let hyprlandBlue = Theme.rgb(0x33CCFF)


// MARK: - Coach card

final class CoachModel: ObservableObject {
    enum Caret: Equatable { case none, up(CGFloat), down }
    @Published var title = ""
    @Published var text = ""
    @Published var caps: [String] = []
    /// One flag per cap once it has been pressed, for steps that want every key.
    @Published var capsDone: [Bool] = []
    @Published var pressed = false
    @Published var done = false
    /// A recall drill: the keys hide behind a hint until asked for.
    @Published var recall = false
    @Published var hidden = false
    @Published var warning: String?
    @Published var button: String?
    @Published var summary: Coach.Summary?
    var final: Bool { summary != nil }
    @Published var canHead = true
    @Published var headLabel = "Skip tour"
    @Published var headSymbol: String?
    @Published var progress: Double = 0
    @Published var caret: Caret = .none
    var tryKeys: () -> Void = {}
    var next: () -> Void = {}
    var headAction: () -> Void = {}
    var reveal: () -> Void = {}
    var tutorial: () -> Void = {}
}

/// One step of a lesson: a plain raised Surface `lg`, pointing at the real target.
struct CoachCardView: View {
    @ObservedObject var model: CoachModel
    static let width: CGFloat = 344
    /// Transparent room around the card for its caret and the float shadow, which reaches about twice its
    /// radius; with less, the panel edge clips it into a visible tinted rectangle. Clicks pass through.
    static let inset = EdgeInsets(top: 32, leading: 52, bottom: 68, trailing: 52)

    var body: some View {
        if let summary = model.summary {
            FinishCardView(model: model, summary: summary).padding(Self.inset)
        } else {
            step
        }
    }

    private var step: some View {
        VStack(alignment: .leading, spacing: 0) {
            // head: lead symbol, Skip or Pause
            HStack(spacing: 8) {
                Image(systemName: model.recall ? "brain" : "keyboard")
                    .font(Theme.symbol())
                    .contentTransition(.symbolEffect(.replace))
                Spacer(minLength: 8)
                if model.canHead {
                    // The Surface head's close slot: Skip (×) or Pause, named in the tooltip.
                    OIconButton(symbol: model.headSymbol ?? "xmark", label: model.headLabel, action: model.headAction)
                        .padding(.trailing, -6)
                }
            }
            .frame(minHeight: 22)
            Text(model.title).textStyle(.title).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.bottom, 4)
            if !model.text.isEmpty {
                Text(model.text).font(Theme.body(13.5)).lineSpacing(2).opacity(0.86)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.caps.isEmpty { keys.padding(.top, 16) }
            if let warning = model.warning {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                    Text(warning).font(Theme.body(12.5)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.well))
                .padding(.top, 14)
            }
            if let button = model.button {
                HStack {
                    Spacer()
                    OButton(button, variant: .primary, shortcut: ["↩"], action: model.next)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 20)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceSunken)
                    Capsule().fill(Theme.accent).frame(width: g.size.width * model.progress)
                }
            }
            .frame(height: 3)
            .padding(.top, 14)
            .animation(Motion.spring, value: model.progress)
        }
        .frame(width: Self.width - 40)
        .surface(.lg, caret: caret)
        .padding(Self.inset)
        .animation(Motion.fadeMedium, value: model.done)
        .animation(Motion.fadeMedium, value: model.hidden)
    }

    /// Large keycaps and the live state beside them. Hidden in a recall drill until the hint.
    private var keys: some View {
        HStack(spacing: 12) {
            if model.hidden {
                // Blank caps, one per key, so you know how many to remember.
                Kbd(keys: model.caps.map { _ in " " }, size: .large).opacity(0.5)
                    .accessibilityHidden(true)
                Button(action: model.reveal) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb").breatheEffect()
                        Text("Hint")
                    }
                }
                .buttonStyle(OButtonStyle(variant: .ghost, size: .sm))
                .tooltip("Show the keys")
            } else {
                Button(action: model.tryKeys) { caps.fixedSize().contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .tooltip("Press the keys, or click them.")
                // A step with a button only shows its keys; the button moves on.
                if model.button == nil { status }
            }
        }
    }

    @ViewBuilder private var caps: some View {
        if model.capsDone.count == model.caps.count, !model.capsDone.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(model.caps.enumerated()), id: \.offset) { i, k in
                    Kbd(keys: [k], size: .large, pressed: model.capsDone[i])
                        .overlay(alignment: .topTrailing) {
                            if model.capsDone[i] {
                                Image(systemName: "checkmark.circle.fill").font(Theme.symbol(Theme.Icon.md, .semibold))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Theme.onAccent, Theme.success)
                                    .background(Circle().fill(Theme.surfaceRaised).padding(-1.5))
                                    .offset(x: 6, y: -6)
                                    .transition(.symbolEffect(.appear))
                            }
                        }
                        .animation(Motion.spring, value: model.capsDone[i])
                }
            }
        } else {
            Kbd(keys: model.caps, size: .large, pressed: model.pressed)
        }
    }

    /// The live state beside the caps. When a long chord leaves no room for the words, only the symbol
    /// shows (with the words as its tooltip) rather than a truncated "Pre…".
    @ViewBuilder private var status: some View {
        if model.done {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                .transition(.symbolEffect(.appear))
                .accessibilityLabel("Done")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else {
            let icon = Image(systemName: "cursorarrow.rays").symbolEffect(.pulse)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    icon
                    Text("Press it now").font(Theme.body(13)).oneLine().fixedSize()
                }
                icon
            }
            .tooltip("Press it now")
            .opacity(0.8)
        }
    }

    private var caret: Caret {
        switch model.caret {
        case .none: .none
        case .up(let x): .top(x)
        case .down: .bottom
        }
    }
}

// MARK: - Finish card

/// The last step of a lesson: a cheat sheet of the keys it taught, at the centre of the screen. The
/// mode chord sits on top, the rest in up to two columns of label rows with their keys on the right.
struct FinishCardView: View {
    @ObservedObject var model: CoachModel
    let summary: Coach.Summary
    static let width: CGFloat = 540
    private static let pad = EdgeInsets(top: 26, leading: 28, bottom: 0, trailing: 28)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Density.xl.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            title
            if !model.text.isEmpty {
                Text(model.text).font(Theme.body()).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if !summary.modeCaps.isEmpty { mode.padding(.top, 14) }
            columns.padding(.top, 16)
            footer.padding(.top, 22).padding(.bottom, 18)
        }
        .padding(Self.pad)
        .frame(width: Self.width, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.accent).frame(height: 3) } // the full progress bar
        .clipShape(shape)
        .foregroundStyle(Theme.ink)
        .background(shape.fill(Theme.surfaceRaised).elevation(.float, in: shape))
    }

    /// Display type; a word in *stars* is set at 500.
    private var title: Text {
        let parts = model.title.split(separator: "*", omittingEmptySubsequences: false)
        return parts.enumerated().reduce(Text("")) { text, part in
            text + Text(part.element).font(Theme.body(34, part.offset.isMultiple(of: 2) ? .light : .medium))
        }
        .tracking(-0.68)
    }

    /// The mode chord on mid-size caps, its name and how to leave, above a hairline.
    private var mode: some View {
        HStack(spacing: 10) {
            Kbd(keys: summary.modeCaps, size: .medium).fixedSize()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.modeName).font(Theme.body(13.5, .medium)).oneLine().fixedSize()
                (Text("Press it first. ") + Text("Esc").font(Theme.keys(12, .medium)) + Text(" or a click leaves it."))
                    .textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var columns: some View {
        let count = summary.groups.map(\.column).max() ?? 1
        return HStack(alignment: .top, spacing: 28) {
            ForEach(1...max(1, count), id: \.self) { col in
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(summary.groups.enumerated()).filter { $0.element.column == col }, id: \.offset) { _, g in
                        group(g)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func group(_ g: Coach.Summary.Group) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OSectionHeader(g.title, tone: Theme.inkMuted).padding(.bottom, Theme.Space.xs)
            ForEach(Array(g.rows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 10) {
                    Text(row.label).font(Theme.body()).oneLine()
                    Spacer(minLength: 8)
                    Kbd(keys: row.caps).fixedSize()
                }
                .frame(minHeight: 30)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) } }
            }
        }
    }

    /// The help hint and the buttons on one line, or the hint above the buttons when both don't fit.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                hint
                Spacer(minLength: 8)
                buttons
            }
            VStack(alignment: .trailing, spacing: 12) {
                hint.frame(maxWidth: .infinity, alignment: .leading)
                buttons
            }
        }
    }

    @ViewBuilder private var hint: some View {
        if let key = summary.helpKey {
            HStack(spacing: 4) {
                Kbd(keys: [key])
                Text("in \(summary.modeName.lowercased()) shows every key on the keyboard")
                    .textStyle(.caption).foregroundStyle(Theme.inkFaint).oneLine()
            }
            .fixedSize()
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if summary.tutorial { OButton("Start the tutorial", variant: .ghost, action: model.tutorial) }
            OButton(model.button ?? "Finish", variant: .primary, shortcut: ["↩"], action: model.next)
                .keyboardShortcut(.defaultAction)
        }
        .fixedSize()
    }
}

// MARK: - Menu bar tip

/// Hangs under the menu bar item during onboarding: a Surface `md` with a caret pointing at the item.
struct MenuBarTipView: View {
    @ObservedObject var model: MenuBarTipModel
    /// Transparent room for the caret and the popover shadow, enough that the panel edge doesn't clip it;
    /// the panel ignores the mouse anyway.
    static let inset = EdgeInsets(top: 18, leading: 32, bottom: 44, trailing: 32)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: model.state == .good ? "checkmark.circle.fill" : "lightbulb")
                .font(Theme.symbol(Theme.Icon.lg))
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
        case .move: "Items on the left hide first. Move Ouch right in Control Center › Edit Controls."
        case .hidden: "Move it right, near the clock, in Control Center › Edit Controls."
        }
    }
}
