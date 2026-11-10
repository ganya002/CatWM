import AppKit
import CatWMKit
import CoreText
import SwiftUI

enum Theme {
    static let palette = Palette.catwm

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func hex(_ value: UInt32, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }

    static func ns(_ token: KeyPath<Palette, Palette.Pair>) -> NSColor {
        NSColor(name: nil) { appearance in
            let workspace = NSWorkspace.shared
            var pair = palette[keyPath: token]
            if workspace.accessibilityDisplayShouldIncreaseContrast {
                if token == \.hairline { pair = palette.borderControl }
                if token == \.inkFaint { pair = palette.inkMuted }
            }
            if workspace.accessibilityDisplayShouldReduceTransparency, token == \.glass {
                pair.lightAlpha = 1
                pair.darkAlpha = 1
            }
            return isDark(appearance) ? hex(pair.dark, pair.darkAlpha) : hex(pair.light, pair.lightAlpha)
        }
    }
    private static func token(_ path: KeyPath<Palette, Palette.Pair>) -> Color { Color(nsColor: ns(path)) }

    static func fixed(_ token: KeyPath<Palette, Palette.Pair>, dark: Bool) -> Color {
        Color(nsColor: nsFixed(token, dark: dark))
    }
    static func nsFixed(_ token: KeyPath<Palette, Palette.Pair>, dark: Bool) -> NSColor {
        let pair = palette[keyPath: token]
        return dark ? hex(pair.dark, pair.darkAlpha) : hex(pair.light, pair.lightAlpha)
    }
    static func rgb(_ value: UInt32, _ alpha: CGFloat = 1) -> Color { Color(nsColor: hex(value, alpha)) }
    static let iconAccent = hex(0x1FAFFF, 1)

    static let background = token(\.background)
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
    static let badge = token(\.badge)
    static let onBadge = token(\.onBadge)
    static let glass = token(\.glass)
    static let wash1 = token(\.wash1)
    static let wash2 = token(\.wash2)

    static let well = Color(nsColor: NSColor(name: nil) { appearance in
        ns(\.ink).resolved(appearance).withAlphaComponent(isDark(appearance) ? 0.09 : 0.06)
    })
    static let wellHover = Color(nsColor: NSColor(name: nil) { appearance in
        ns(\.ink).resolved(appearance).withAlphaComponent(isDark(appearance) ? 0.15 : 0.1)
    })

    static let thumbMain = Color(nsColor: NSColor(name: nil) { appearance in
        let accent = ns(\.accent).resolved(appearance), tint = ns(\.tint).resolved(appearance)
        return accent.blended(withFraction: 0.45, of: tint) ?? accent
    })

    static let wash = LinearGradient(stops: [.init(color: wash1, location: 0), .init(color: background, location: 0.55),
                                             .init(color: wash2, location: 1)],
                                     startPoint: UnitPoint(x: 0.1, y: 0), endPoint: UnitPoint(x: 0.9, y: 1))

    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        let fonts = urls.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
    }

    private static let brandSemibold = "PilcrowRounded-Semibold"
    private static let brandBold = "PilcrowRounded-Bold"
    private static let hasBrandFace = NSFont(name: brandSemibold, size: 12) != nil
        && NSFont(name: brandBold, size: 12) != nil
    private static let headerBold = "Alpino-Bold"
    private static let hasHeaderFace = NSFont(name: headerBold, size: 12) != nil

    private static let keysDescriptor = NSFontDescriptor(fontAttributes: [
        .name: brandSemibold,
        .cascadeList: [NSFont.systemFont(ofSize: 12, weight: .semibold).fontDescriptor]
    ])

    static func body(_ size: CGFloat = 13.5, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func keys(_ size: CGFloat = 12.5, _ weight: Font.Weight = .regular) -> Font {
        guard hasBrandFace, let font = NSFont(descriptor: keysDescriptor, size: size) else {
            return .system(size: size, weight: weight)
        }
        return Font(font)
    }
    static func mono(_ size: CGFloat = 11.5, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func heading(_ size: CGFloat = 15) -> Font {
        hasHeaderFace ? .custom(headerBold, size: size) : .system(size: size, weight: .semibold)
    }
    static func display(_ size: CGFloat) -> Font {
        hasHeaderFace ? .custom(headerBold, size: size) : .system(size: size, weight: .bold)
    }
    static func wordmark(_ size: CGFloat) -> Font {
        hasBrandFace ? .custom(brandBold, size: size) : .system(size: size, weight: .bold)
    }

    static func nsBody(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    enum Icon {
        static let extraSmall: CGFloat = 9, small: CGFloat = 11, medium: CGFloat = 13, large: CGFloat = 15
        static let extraLarge: CGFloat = 22
    }
    static func symbol(_ size: CGFloat = Icon.medium, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    enum Radius {
        static let extraSmall: CGFloat = 4, small: CGFloat = 6, medium: CGFloat = 8, large: CGFloat = 12
        static let extraLarge: CGFloat = 18
        static let pane: CGFloat = 14
        static let hud: CGFloat = 22
        static let xxl: CGFloat = 24
    }
    enum Space {
        static let xxs: CGFloat = 2, extraSmall: CGFloat = 4, small: CGFloat = 8, medium: CGFloat = 12
        static let large: CGFloat = 16, extraLarge: CGFloat = 24, xxl: CGFloat = 32
        static let page: CGFloat = 36
    }
    static let rowHeight: CGFloat = 30
    static let controlHeight: CGFloat = 28
 static let keycapSize: CGFloat = 20
    static let menuWidth: CGFloat = 272
    static let submenuWidth: CGFloat = 232

    static let fast = 0.12, medium = 0.18, slow = 0.28, linger = 0.45
}

#if DEBUG
extension GalleryExamples {
    static let colours = GalleryExample(order: 0) { AnyView(GalleryContent(model: $0).colours) }
}

extension GalleryContent {
    @ViewBuilder var colours: some View {
        block("Colour (hex: light / dark)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Space.medium)], alignment: .leading,
                      spacing: Theme.Space.medium) {
                ForEach(ColorToken.all) { token in
                    VStack(alignment: .leading, spacing: Theme.Space.extraSmall) {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(Color(nsColor: Theme.ns(token.path)))
                            .frame(height: 36)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1))
                        Text(token.name).font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                        Text(hex(token.path)).font(Theme.mono(11, .regular)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }
}
#endif

extension NSColor {
    func resolved(_ appearance: NSAppearance) -> NSColor {
        var out = self
        appearance.performAsCurrentDrawingAppearance { out = self.usingColorSpace(.sRGB) ?? self }
        return out
    }
}
