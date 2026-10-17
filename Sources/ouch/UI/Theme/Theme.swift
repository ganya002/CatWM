import AppKit
import CoreText
import SwiftUI

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
