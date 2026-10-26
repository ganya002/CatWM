import AppKit
import SwiftUI

/// CatWM's palette, cut to what Minimal Cat draws: black and white grounds, one sky accent.
enum Theme {
    private static func pair(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            let solid = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: solid ? 1 : alpha)
        })
    }

    static let surface = pair(0xF4F4F4, 0x141414)
    static let raised = pair(0xFFFFFF, 0x1C1C1C)
    static let hover = pair(0xE8E8E8, 0x262626)
    static let hairline = pair(0xE0E0E0, 0x2A2A2A)
    static let ink = pair(0x000000, 0xFFFFFF)
    static let inkMuted = pair(0x5C5C5C, 0xA3A3A3)
    static let accent = pair(0x1FAFFF, 0x1FAFFF)
    static let onAccent = pair(0x000000, 0x000000)
    static let glass = pair(0xFFFFFF, 0x141414, alpha: 0.86)

    static let fast = 0.12
    static let easeOut = Animation.easeOut(duration: fast)
    static let spring = Animation.spring(response: 0.28, dampingFraction: 0.82)

    static func keycap(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static let title = Font.system(size: 22, weight: .bold, design: .rounded)
    static let body = Font.system(size: 13.5)
    static let caption = Font.system(size: 12)
    static let label = Font.system(size: 12, weight: .medium)
}

/// One key as a small rounded cap.
struct Keycap: View {
    let text: String
    var size: CGFloat = 22

    var body: some View {
        Text(text)
            .font(Theme.keycap(size * 0.5))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, size * 0.28)
            .frame(minWidth: size, minHeight: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            .accessibilityLabel(Self.spoken(text))
    }

    static func spoken(_ text: String) -> String {
        ["←": "Left Arrow", "→": "Right Arrow", "↑": "Up Arrow", "↓": "Down Arrow", "↩": "Return", "⇪": "Caps Lock",
         ",": "Comma", ".": "Period"][text] ?? text
    }
}

extension View {
    /// The floating glass card every Minimal Cat surface uses.
    func floatingCard(radius: CGFloat = 18) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.glass))
        }
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }
}
