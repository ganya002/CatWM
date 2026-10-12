import AppKit
import CoreText
import SwiftUI

/// Fonts, colours and small controls shared by the Settings window, HUD and menu bar.
enum Theme {
    // MARK: Fonts

    /// Text uses Apple's system fonts (San Francisco, SF Mono). Only Dela Gothic One (OFL; logo and
    /// welcome title) ships in Contents/Resources/Fonts.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        let fonts = urls.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
    }

    private static let hasDela = NSFont(name: "DelaGothicOne-Regular", size: 12) != nil

    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Pane titles, card headings and HUD text: plain bold body face.
    static func heading(_ size: CGFloat) -> Font { body(size, .bold) }

    /// Dela Gothic One, reserved for the few moments that deserve emphasis: the logo and the welcome title.
    static func display(_ size: CGFloat) -> Font {
        hasDela ? .custom("DelaGothicOne-Regular", size: size) : body(size, .bold)
    }

    static func nsHeading(_ size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .bold)
    }
    static func nsMono(_ size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: Colours (system semantic colours, so light/dark, Increase Contrast and accent colour all follow macOS)

    static let window = Color(nsColor: .windowBackgroundColor)
    static let statusBar = Color(nsColor: .windowBackgroundColor)
    /// Raised controls: chips, keycaps.
    static let control = Color(nsColor: .controlColor)
    /// Grouped-form box fill, as in System Settings.
    static let card = Color(nsColor: .quaternarySystemFill)
    static let hairline = Color(nsColor: .separatorColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    /// Plain windows in the miniatures: light like the icon's, a step above the card in dark mode.
    static let miniWindow = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.42, alpha: 1) : .white
    })
}

// MARK: - Layout pieces

/// Grouped box: rounded tint with a hairline, and a separator between each child view.
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        _VariadicView.Tree(Separated()) { content }
            .padding(.horizontal, 12)
            .padding(.vertical, padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
    }

    private struct Separated: _VariadicView_MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(children) { child in
                    child.overlay(alignment: .top) {
                        if child.id != children.first?.id { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    }
                }
            }
        }
    }
}

/// Section title above a card, with an optional footnote below it.
struct Block<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(Theme.body(13, .semibold)).foregroundStyle(.primary)
                    .padding(.leading, 2).padding(.bottom, 6)
            }
            content
            if let footer {
                Text(footer).font(Theme.body(11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2).padding(.top, 6)
            }
        }
    }
}

/// One line in a card: label on the left, control on the right.
struct Row<Label: View, Control: View>: View {
    var vertical: CGFloat = 9
    @ViewBuilder var label: Label
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            label
            Spacer(minLength: 0)
            control
        }
        .padding(.vertical, vertical)
    }
}

extension Row where Label == Text {
    init(_ title: String, vertical: CGFloat = 9, @ViewBuilder control: () -> Control) {
        self.init(vertical: vertical, label: { Text(title) }, control: control)
    }
}

/// Title with a smaller grey explanation underneath.
struct TitleDetail: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(Theme.body(11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Switch row; dims its label when disabled, like System Settings.
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Row {
            Group { if let detail { TitleDetail(title: title, detail: detail) } else { Text(title) } }
                .opacity(enabled ? 1 : 0.4)
        } control: {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }
}

// MARK: - Controls (native AppKit-backed controls, so focus, keyboard and VoiceOver all work)

/// Segmented control.
struct Segmented<T: Hashable>: View {
    /// Spoken by VoiceOver; not shown.
    let title: String
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// Pop-up button. `bordered: false` shows just the value and the ⇕ arrows, as in the design.
struct PopUp<T: Hashable>: View {
    /// Spoken by VoiceOver; not shown.
    let title: String
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var bordered = false

    var body: some View {
        let picker = Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        if bordered { picker } else { picker.buttonStyle(.borderless) }
    }
}

/// Grey circle with a white minus, used to delete list rows.
struct RemoveButton: View {
    let help: String
    let action: () -> Void
    private final class Hover: ObservableObject { @Published var on = false }
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            Circle().fill(Color.primary.opacity(hover.on ? 0.45 : 0.3))
                .frame(width: 16, height: 16)
                .overlay(Capsule().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 8, height: 2))
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Rounded gradient square holding a white glyph (sidebar and hero icons).
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 0.75)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.56, weight: .medium))
                    .imageScale(.medium)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.03, y: size * 0.02)
                    .contentTransition(.symbolEffect(.replace))
            )
            .animation(.default, value: symbol)
    }
}

/// White keycaps for a shortcut.
struct Keycaps: View {
    let caps: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, c in
                Text(c)
                    .font(Theme.body(12, .medium))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.control))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3)))
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            }
        }
    }
}

// MARK: - Motion

/// Ouch's bit of personality, taken from the icon: things land with a small squish and a burst of the
/// icon's yellow impact lines. Reserved for state changes (a layout joins the cycle, a permission is
/// granted, a preview window lands), never for navigation, and dropped under Reduce Motion.
enum Motion {
    /// Springy settle for things snapping into place.
    static let snap = Animation.spring(response: 0.34, dampingFraction: 0.7)
    /// `snap`, or a plain short fade-friendly ease under Reduce Motion.
    static func snap(_ reduce: Bool) -> Animation { reduce ? .easeOut(duration: 0.15) : snap }
}

/// Three short strokes bursting from a point, like the ones on the app icon.
struct SparkLines: Shape {
    /// Direction of the middle stroke in degrees, y down: -90 points up, -135 up and to the left.
    var angle: Double = -135

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        for (spread, reach) in [(-40.0, 0.78), (0, 1), (40, 0.78)] {
            let a = (angle + spread) * .pi / 180
            p.move(to: CGPoint(x: c.x + cos(a) * r * 0.4, y: c.y + sin(a) * r * 0.4))
            p.addLine(to: CGPoint(x: c.x + cos(a) * r * reach, y: c.y + sin(a) * r * reach))
        }
        return p
    }
}

/// The icon's impact lines, flashing once each time `trigger` changes.
struct ImpactBurst<Trigger: Equatable>: View {
    let trigger: Trigger
    var angle: Double = -135
    var size: CGFloat = 22
    /// Seconds to wait first, e.g. until a moving window lands.
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: CaseIterable { case rest, burst, fade }

    var body: some View {
        let reduceMotion = reduceMotion, delay = delay
        return SparkLines(angle: angle)
            .stroke(Color.yellow, style: StrokeStyle(lineWidth: max(1.5, size / 10), lineCap: .round))
            .frame(width: size, height: size)
            .phaseAnimator(Phase.allCases, trigger: trigger) { view, phase in
                view.scaleEffect(phase == .rest ? 0.3 : phase == .burst ? 1 : 1.2)
                    .opacity(reduceMotion || phase != .burst ? 0 : 1)
            } animation: { phase in
                switch phase {
                case .rest: nil
                case .burst: .spring(response: 0.2, dampingFraction: 0.6).delay(delay)
                case .fade: .easeOut(duration: 0.3).delay(0.08)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct Squish<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    let delay: Double
    let anchor: UnitPoint
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let on = enabled && !reduceMotion, delay = delay
        return content.keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: trigger) { view, s in
            view.scaleEffect(x: on ? s.width : 1, y: on ? s.height : 1, anchor: anchor)
        } keyframes: { _ in
            let wobble = Spring(response: 0.38, dampingRatio: 0.42)
            KeyframeTrack(\.width) {
                LinearKeyframe(1, duration: max(delay, 0.001))
                CubicKeyframe(1.09, duration: 0.07)
                SpringKeyframe(1, duration: 0.5, spring: wobble)
            }
            KeyframeTrack(\.height) {
                LinearKeyframe(1, duration: max(delay, 0.001))
                CubicKeyframe(0.9, duration: 0.07)
                SpringKeyframe(1, duration: 0.5, spring: wobble)
            }
        }
    }
}

extension View {
    /// Squashes and springs back, as if it just bumped into something, each time `trigger` changes
    /// (only while `when` holds, so e.g. joining bumps but leaving doesn't).
    func squish<T: Equatable>(on trigger: T, when: Bool = true, delay: Double = 0, anchor: UnitPoint = .bottom) -> some View {
        modifier(Squish(trigger: trigger, delay: delay, anchor: anchor, enabled: when))
    }
}

// MARK: - Miniatures

/// A window in the miniatures, styled like the icon: the main window in the accent colour, the rest
/// plain. `chrome` adds the title-bar dots on larger ones.
struct MiniWindow: View {
    var main: Bool
    var muted = false
    var corner: CGFloat = 2.5
    var chrome = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        shape.fill(fill)
            .overlay(shape.strokeBorder(main && !muted ? Color.white.opacity(0.3) : Theme.hairline, lineWidth: 0.75))
            .overlay(alignment: .topLeading) {
                if chrome {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(main ? Color.white.opacity(0.5) : Color.primary.opacity(0.18)).frame(width: 4, height: 4)
                        }
                    }
                    .padding(5)
                }
            }
    }

    private var fill: AnyShapeStyle {
        if main { return AnyShapeStyle((muted ? Color.gray : Color.accentColor).gradient) }
        return muted ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(Theme.miniWindow.gradient)
    }
}

/// Miniature of a layout, drawn with the real layout code. When the layout changes, the windows
/// spring to their new places.
struct LayoutThumbnail: View {
    let layout: Layout
    var count = 4
    var selected = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let frames = Self.frames(layout, count: count, size: g.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(selected ? 0.1 : 0.07))
                ForEach(Array(frames.enumerated()).reversed(), id: \.offset) { i, f in
                    MiniWindow(main: i == 0, muted: !selected)
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.minX, y: f.minY)
                }
            }
        }
        .animation(Motion.snap(reduceMotion), value: layout)
        .animation(.easeOut(duration: 0.2), value: selected)
        .accessibilityHidden(true)
    }

    private static func frames(_ layout: Layout, count: Int, size: CGSize) -> [CGRect] {
        let px = size.width * 0.04, py = size.height * 0.06
        let r = CGRect(origin: .zero, size: size).insetBy(dx: px, dy: py)
        return layout.frames(count: count, in: r.insetBy(dx: -px / 2, dy: -py / 2), ratio: 0.5, mainCount: 1)?
            .map { $0.insetBy(dx: px / 2, dy: py / 2) }
            ?? [CGRect(x: size.width * 0.09, y: size.height * 0.15, width: size.width * 0.52, height: size.height * 0.5),
                CGRect(x: size.width * 0.39, y: size.height * 0.37, width: size.width * 0.52, height: size.height * 0.5)]
    }
}

/// The app icon with a status badge in its corner; the badge symbol swaps with a bounce.
struct BadgedAppIcon: View {
    let badge: String
    let color: Color
    var size: CGFloat = 48

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: badge)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, color)
                    .background(Circle().fill(Theme.window).padding(-1.5))
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: size * 0.06, y: size * 0.04)
            }
            .animation(.default, value: badge)
            .accessibilityHidden(true)
    }
}
