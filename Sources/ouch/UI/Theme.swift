import AppKit
import CoreText
import SwiftUI

struct Palette {
    struct Pair {
        let light: UInt32, dark: UInt32
        var lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1
        init(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) {
            self.light = light; self.dark = dark; lightAlpha = alpha.0; darkAlpha = alpha.1
        }
    }

    var bg, surface, surfaceRaised, surfaceSunken, hover, hairline, borderControl: Pair
    var ink, inkMuted, inkFaint: Pair
    var accent, accentHover, onAccent, accentInk, accentSoft, tint, focus: Pair
    var success, warning, danger, dangerSoft: Pair
    var glass, wash1, wash2: Pair

    static let ouch = Palette(
        bg: Pair(0xF4F4F6, 0x1B1B1E), surface: Pair(0xFFFFFF, 0x232326), surfaceRaised: Pair(0xFFFFFF, 0x2C2C30),
        surfaceSunken: Pair(0xECECF0, 0x18181B), hover: Pair(0xECECF0, 0x36363B), hairline: Pair(0xE2E2E7, 0x38383D),
        borderControl: Pair(0x7E7E87, 0x7A7A82),
        ink: Pair(0x18181B, 0xF5F5F7), inkMuted: Pair(0x55555C, 0xB4B4BB), inkFaint: Pair(0x68686F, 0x97979F),
        accent: Pair(0x0A68E6, 0x3F95FF), accentHover: Pair(0x0A58C4, 0x5AA8FF), onAccent: Pair(0xFFFFFF, 0x0B0B0D),
        accentInk: Pair(0x0A5FD1, 0x8DC3FF), accentSoft: Pair(0xE3EEFF, 0x1B2C47),
        tint: Pair(0xC7C7CC, 0x4A4A50), focus: Pair(0x0A68E6, 0x8DC3FF),
        success: Pair(0x1F7A3D, 0x5FD38A), warning: Pair(0x8A5A00, 0xFFCC00), danger: Pair(0xC42B1C, 0xFF7B6B),
        dangerSoft: Pair(0xFDE8E6, 0x3D2220),
        glass: Pair(0xFFFFFF, 0x2C2C30, alpha: (0.82, 0.80)), wash1: Pair(0xDDE9FB, 0x1F2C42), wash2: Pair(0xE5E5E8, 0x2B2B2F))
}

enum Theme {
    static var palette = Palette.ouch

    static func isDark(_ a: NSAppearance) -> Bool { a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    private static func hex(_ v: UInt32, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    static func ns(_ token: KeyPath<Palette, Palette.Pair>) -> NSColor {
        NSColor(name: nil) { a in
            let p = palette[keyPath: token]
            return isDark(a) ? hex(p.dark, p.darkAlpha) : hex(p.light, p.lightAlpha)
        }
    }
    private static func token(_ kp: KeyPath<Palette, Palette.Pair>) -> Color { Color(nsColor: ns(kp)) }

    static func fixed(_ token: KeyPath<Palette, Palette.Pair>, dark: Bool) -> Color {
        let p = palette[keyPath: token]
        return Color(nsColor: dark ? hex(p.dark, p.darkAlpha) : hex(p.light, p.lightAlpha))
    }
    static func nsFixed(_ token: KeyPath<Palette, Palette.Pair>, dark: Bool) -> NSColor {
        let p = palette[keyPath: token]
        return dark ? hex(p.dark, p.darkAlpha) : hex(p.light, p.lightAlpha)
    }
    static func rgb(_ v: UInt32, _ alpha: CGFloat = 1) -> Color { Color(nsColor: hex(v, alpha)) }
    static let iconBlue = hex(0x0A74FF, 1)

    static let bg = token(\.bg)
    static let surface = token(\.surface)
    static let surfaceRaised = token(\.surfaceRaised)
    static let surfaceSunken = token(\.surfaceSunken)
    static let hover = token(\.hover)
    static let hairline = token(\.hairline)
    static let borderControl = token(\.borderControl)
    static let ink = token(\.ink)
    static let inkMuted = token(\.inkMuted)
    static let inkFaint = token(\.inkFaint)
    static let accent = token(\.accent)
    static let accentHover = token(\.accentHover)
    static let onAccent = token(\.onAccent)
    static let accentInk = token(\.accentInk)
    static let accentSoft = token(\.accentSoft)
    static let tint = token(\.tint)
    static let focus = token(\.focus)
    static let success = token(\.success)
    static let warning = token(\.warning)
    static let danger = token(\.danger)
    static let dangerSoft = token(\.dangerSoft)
    static let glass = token(\.glass)
    static let wash1 = token(\.wash1)
    static let wash2 = token(\.wash2)

    static let well = Color(nsColor: NSColor(name: nil) { a in
        ns(\.ink).resolved(a).withAlphaComponent(isDark(a) ? 0.09 : 0.06)
    })
    static let wellHover = Color(nsColor: NSColor(name: nil) { a in
        ns(\.ink).resolved(a).withAlphaComponent(isDark(a) ? 0.15 : 0.1)
    })

    static let thumbMain = Color(nsColor: NSColor(name: nil) { a in
        let accent = ns(\.accent).resolved(a), tint = ns(\.tint).resolved(a)
        return accent.blended(withFraction: 0.45, of: tint) ?? accent
    })

    static let wash = LinearGradient(stops: [.init(color: wash1, location: 0), .init(color: bg, location: 0.55),
                                             .init(color: wash2, location: 1)],
                                     startPoint: UnitPoint(x: 0.1, y: 0), endPoint: UnitPoint(x: 0.9, y: 1))

    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        let fonts = urls.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
    }

    private static let hasChillaxBold = NSFont(name: "Chillax-Bold", size: 12) != nil
    private static let hasChillax = NSFont(name: "Chillax-Regular", size: 12) != nil

    private static func chillax(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: "Chillax-Light"
        case .regular: "Chillax-Regular"
        default: "Chillax-Medium"
        }
    }

    static func body(_ size: CGFloat = 13.5, _ weight: Font.Weight = .regular) -> Font {
        hasChillax ? .custom(chillax(weight), size: size) : .system(size: size, weight: weight)
    }
    static func keys(_ size: CGFloat = 12.5, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat = 11.5, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func heading(_ size: CGFloat = 15) -> Font { body(size, .medium) }
    static func display(_ size: CGFloat) -> Font { body(size, .light) }
    static func wordmark(_ size: CGFloat) -> Font {
        hasChillaxBold ? .custom("Chillax-Bold", size: size) : .system(size: size, weight: .bold)
    }

    static func nsBody(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name = weight.rawValue < NSFont.Weight.regular.rawValue ? "Chillax-Light"
            : weight == .regular ? "Chillax-Regular" : "Chillax-Medium"
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    enum Icon {
        static let xs: CGFloat = 9, sm: CGFloat = 11, md: CGFloat = 13, lg: CGFloat = 15, xl: CGFloat = 22
    }
    static func symbol(_ size: CGFloat = Icon.md, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    enum Radius {
        static let xs: CGFloat = 4, sm: CGFloat = 6, md: CGFloat = 8, lg: CGFloat = 12, xl: CGFloat = 18
        static let pane: CGFloat = 14
        static let hud: CGFloat = 22
        static let xxl: CGFloat = 24
    }
    enum Space {
        static let xxs: CGFloat = 2, xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16
        static let xl: CGFloat = 24, xxl: CGFloat = 32
        static let page: CGFloat = 36
    }
    static let rowHeight: CGFloat = 30
    static let controlHeight: CGFloat = 28
    static let menuWidth: CGFloat = 272
    static let submenuWidth: CGFloat = 232

    static let fast = 0.12, medium = 0.18, slow = 0.28, linger = 0.45
}

extension NSColor {
    func resolved(_ appearance: NSAppearance) -> NSColor {
        var out = self
        appearance.performAsCurrentDrawingAppearance { out = self.usingColorSpace(.sRGB) ?? self }
        return out
    }
}

extension View {
    func oneLine(_ mode: Text.TruncationMode = .tail) -> some View { lineLimit(1).truncationMode(mode) }

    func kicker(_ color: Color = Theme.accentInk) -> some View {
        font(Theme.mono(11, .medium)).tracking(0.88).textCase(.uppercase).foregroundStyle(color)
    }

    func textStyle(_ style: TextStyle) -> some View { font(style.font).tracking(style.tracking) }
}

extension Text {
    func textStyle(_ style: TextStyle) -> Text { font(style.font).tracking(style.tracking) }
}

enum TextStyle {
    case largeTitle
    case title
    case sectionTitle
    case caption

    var font: Font {
        switch self {
        case .largeTitle: Theme.display(40)
        case .title: Theme.body(22)
        case .sectionTitle: Theme.body(12, .medium)
        case .caption: Theme.body(12)
        }
    }
    var tracking: CGFloat {
        switch self {
        case .largeTitle: -1
        case .title: -0.2
        case .sectionTitle: 0.24
        case .caption: 0
        }
    }
}

enum Motion {
    static let easeOut = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: Theme.medium)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let snap = Animation.spring(response: 0.34, dampingFraction: 0.7)
    static func snap(_ reduce: Bool) -> Animation { reduce ? fade : snap }
    static let fade = Animation.easeOut(duration: Theme.fast)
    static let fadeMedium = Animation.easeOut(duration: Theme.medium)
    static let fadeSlow = Animation.easeOut(duration: Theme.slow)
    static let fadeAway = Animation.easeOut(duration: Theme.linger)
    static let exit = Animation.easeIn(duration: Theme.fast)
    static let pop = Animation.spring(response: 0.36, dampingFraction: 0.8)

    enum Curve {
        static let easeOut = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        static let settle = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)
        static let exit = CAMediaTimingFunction(name: .easeIn)
        static let fade = CAMediaTimingFunction(name: .easeOut)
    }
}

enum Elevation { case sm, knob, popover, float }

extension View {
    func elevation<S: Shape>(_ e: Elevation, in shape: S) -> some View {
        let ring = Theme.hairline
        let drop = Color(nsColor: NSColor(name: nil) { a in
            let dark = Theme.isDark(a)
            switch e {
            case .sm: return NSColor.black.withAlphaComponent(dark ? 0.4 : 0.06)
            case .knob: return NSColor.black.withAlphaComponent(0.32)
            case .popover: return NSColor.black.withAlphaComponent(dark ? 0.65 : 0.22)
            case .float: return NSColor.black.withAlphaComponent(dark ? 0.75 : 0.35)
            }
        })
        let (radius, y): (CGFloat, CGFloat) = switch e {
        case .sm: (1, 1)
        case .knob: (2, 0)
        case .popover: (13, 10)
        case .float: (22, 18)
        }
        return self
            .overlay(shape.stroke(ring, lineWidth: e == .popover || e == .float ? 1 : 0))
            .shadow(color: drop, radius: radius, y: y)
    }

    func legible(strong: Bool = false) -> some View {
        shadow(color: .black.opacity(strong ? 0.45 : 0.3), radius: strong ? 8 : 12, y: strong ? 2 : 4)
    }
}

enum Density {
    case xs, sm, md, lg, xl

    var radius: CGFloat {
        switch self {
        case .xs: Theme.Radius.md
        case .sm, .md: Theme.Radius.lg
        case .lg: Theme.Radius.xl
        case .xl: Theme.Radius.xxl
        }
    }
    var padding: EdgeInsets {
        switch self {
        case .xs: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
        case .sm: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .md: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        case .lg: EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20)
        case .xl: EdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32)
        }
    }
    var elevation: Elevation { self == .xs || self == .md ? .popover : .float }
}

enum Caret: Equatable {
    case none
    case top(CGFloat)
    case bottom
    case bottomAt(CGFloat)
    case leading(CGFloat)
    case leadingBottom(CGFloat)
}

private struct SurfaceModifier: ViewModifier {
    let density: Density
    let glass: Bool
    let caret: Caret

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: density.radius, style: .continuous)
        content
            .padding(density.padding)
            .foregroundStyle(Theme.ink)
            .background(alignment: caretAlignment) { caretView }
            .background { fill(shape) }
    }

    @ViewBuilder private func fill(_ shape: RoundedRectangle) -> some View {
        if glass {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(Theme.glass).background(VisualBlur(radius: density.radius))
                    .background(shape.fill(Color.clear).elevation(density.elevation, in: shape))
            }
        } else {
            shape.fill(Theme.surfaceRaised).elevation(density.elevation, in: shape)
        }
    }

    private var caretAlignment: Alignment {
        switch caret {
        case .bottom, .bottomAt: return .bottom
        case .leadingBottom: return .bottomLeading
        default: return .topLeading
        }
    }

    @ViewBuilder private var caretView: some View {
        let diamond = RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.surfaceRaised)
            .frame(width: 14, height: 14).rotationEffect(.degrees(45))
        switch caret {
        case .none: EmptyView()
        case .top(let x): diamond.offset(x: x - 7, y: -6)
        case .bottom: diamond.offset(y: 6)
        case .bottomAt(let x): diamond.offset(x: x, y: 6)
        case .leading(let y): diamond.offset(x: -6, y: y - 7)
        case .leadingBottom(let y): diamond.offset(x: -6, y: 7 - y)
        }
    }
}

extension View {
    func surface(_ density: Density, glass: Bool = false, caret: Caret = .none) -> some View {
        modifier(SurfaceModifier(density: density, glass: glass, caret: caret))
    }

    func pane() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.pane, style: .continuous)
        return clipShape(shape).background(shape.fill(Theme.surface).elevation(.popover, in: shape))
    }
}

private struct FloatingGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(Theme.glass))
                .background(VisualBlur(radius: 18).clipShape(shape))
                .background(shape.fill(Theme.glass).elevation(.float, in: shape))
        }
    }
}

extension View {
    func floatingGlass<S: InsettableShape>(_ shape: S) -> some View { modifier(FloatingGlass(shape: shape)) }
}

struct VisualBlur: NSViewRepresentable {
    var radius: CGFloat
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.state = .active
        v.blendingMode = .behindWindow
        v.maskImage = Self.mask(radius)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    private static func mask(_ radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

extension View {
    @ViewBuilder func rotateEffect<V: Equatable>(value: V) -> some View {
        if #available(macOS 15.0, *) {
            symbolEffect(.rotate, options: .speed(2.2), value: value)
        } else {
            symbolEffect(.bounce, options: .speed(2), value: value)
        }
    }
    @ViewBuilder func wiggleEffect<V: Equatable>(value: V) -> some View {
        if #available(macOS 15.0, *) { symbolEffect(.wiggle, value: value) } else { symbolEffect(.bounce, value: value) }
    }
    @ViewBuilder func breatheEffect(isActive: Bool = true) -> some View {
        if #available(macOS 15.0, *) { symbolEffect(.breathe, isActive: isActive) } else { symbolEffect(.pulse, isActive: isActive) }
    }
    @ViewBuilder func drawOnEffect(isActive: Bool) -> some View {
        if #available(macOS 26.0, *) { symbolEffect(.drawOn, isActive: !isActive) } else { self }
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
    func squish<T: Equatable>(on trigger: T, when: Bool = true, delay: Double = 0, anchor: UnitPoint = .bottom) -> some View {
        modifier(Squish(trigger: trigger, delay: delay, anchor: anchor, enabled: when))
    }
}

struct DemoApp: Equatable {
    let title: String
    let dark: Bool
    let r: Double, g: Double, b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    static let all: [DemoApp] = [
        DemoApp(title: "Terminal", dark: true, r: 0.13, g: 0.13, b: 0.15),
        DemoApp(title: "Notes", dark: false, r: 0.95, g: 0.95, b: 0.96),
        DemoApp(title: "Music", dark: true, r: 0.2, g: 0.21, b: 0.26),
        DemoApp(title: "Mail", dark: false, r: 0.88, g: 0.92, b: 0.97),
        DemoApp(title: "Code", dark: true, r: 0.11, g: 0.15, b: 0.21),
        DemoApp(title: "Messages", dark: false, r: 0.86, g: 0.94, b: 0.9),
        DemoApp(title: "Photos", dark: true, r: 0.26, g: 0.19, b: 0.26),
        DemoApp(title: "Calendar", dark: false, r: 0.98, g: 0.93, b: 0.89),
        DemoApp(title: "Finder", dark: false, r: 0.92, g: 0.9, b: 0.98),
        DemoApp(title: "Maps", dark: false, r: 0.89, g: 0.93, b: 0.85),
        DemoApp(title: "Figma", dark: true, r: 0.16, g: 0.2, b: 0.18),
        DemoApp(title: "Podcasts", dark: true, r: 0.24, g: 0.17, b: 0.14),
    ]

    static func pick(avoiding taken: [DemoApp] = []) -> DemoApp {
        (all.filter { !taken.contains($0) }.randomElement() ?? all.randomElement())!
    }
}

struct DemoWindow: View {
    let app: DemoApp
    var main = false
    var corner: CGFloat = 4

    private static let lights = [Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                                 Color(red: 0.16, green: 0.79, blue: 0.25)]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        GeometryReader { g in
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Self.lights[i].opacity(app.dark ? 0.85 : 1)).frame(width: 4, height: 4)
                }
                if g.size.width > 56 {
                    Text(app.title)
                        .font(Theme.body(6.5, .medium))
                        .foregroundStyle(app.dark ? Color.white.opacity(0.6) : Color.black.opacity(0.55))
                        .lineLimit(1)
                        .padding(.leading, 3)
                }
            }
            .padding(.horizontal, 5).padding(.top, 5)
            .opacity(g.size.width > 26 && g.size.height > 14 ? 1 : 0)
        }
        .background(app.color)
        .clipShape(shape)
        .overlay(shape.strokeBorder(main ? Theme.accent : (app.dark ? Color.white : Color.black).opacity(0.1),
                                    lineWidth: main ? 1.25 : 0.5))
    }
}

struct LayoutThumbnail: View {
    let layout: Layout
    var count = 4
    var selected = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let frames = Self.frames(layout, count: count, size: g.size)
            let r = max(1.5, min(g.size.width, g.size.height) * 0.05)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()).reversed(), id: \.offset) { i, f in
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(i == 0 ? (selected ? Theme.accent : Theme.thumbMain) : Theme.tint)
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.minX, y: f.minY)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .animation(Motion.snap(reduceMotion), value: layout)
        .animation(Motion.fadeMedium, value: selected)
        .accessibilityHidden(true)
    }

    private static func frames(_ layout: Layout, count: Int, size: CGSize) -> [CGRect] {
        let gap = max(1.5, size.width * 0.035)
        let r = CGRect(origin: .zero, size: size)
        return layout.frames(count: count, in: r.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: 0.5, mainCount: 1)?
            .map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
            ?? [CGRect(x: size.width * 0.06, y: size.height * 0.1, width: size.width * 0.56, height: size.height * 0.56),
                CGRect(x: size.width * 0.38, y: size.height * 0.34, width: size.width * 0.56, height: size.height * 0.56)]
    }
}

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
                    .font(Theme.symbol(size * 0.36, .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.surface, color)
                    .background(Circle().fill(Theme.surface).padding(-1.5))
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: size * 0.06, y: size * 0.04)
            }
            .animation(.default, value: badge)
            .accessibilityHidden(true)
    }
}
