import AppKit
import CatWMKit
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

    var background, surface, surfaceRaised, surfaceSunken, hover, hairline, borderControl: Pair
    var ink, inkMuted, inkFaint: Pair
    var accent, accentHover, onAccent, accentInk, accentSoft, tint, focus: Pair
    var success, warning, danger, dangerSoft, badge, onBadge: Pair
    var glass, wash1, wash2: Pair

    static let catwm = Palette(
        background: Pair(0xFFFFFF, 0x000000), surface: Pair(0xF4F4F4, 0x141414),
        surfaceRaised: Pair(0xFFFFFF, 0x1C1C1C),
        surfaceSunken: Pair(0xECECEC, 0x0A0A0A), hover: Pair(0xE8E8E8, 0x262626), hairline: Pair(0xE0E0E0, 0x2A2A2A),
        borderControl: Pair(0x7A7A7A, 0x6B6B6B),
        ink: Pair(0x000000, 0xFFFFFF), inkMuted: Pair(0x5C5C5C, 0xA3A3A3), inkFaint: Pair(0x6E6E6E, 0x8A8A8A),
        accent: Pair(0x1FAFFF, 0x1FAFFF), accentHover: Pair(0x0A9BF0, 0x4DC0FF), onAccent: Pair(0x000000, 0x000000),
        accentInk: Pair(0x0072C2, 0x1FAFFF), accentSoft: Pair(0xDFF2FF, 0x0E2638),
        tint: Pair(0xC8C8C8, 0x3A3A3A), focus: Pair(0x000000, 0xFFFFFF),
        success: Pair(0x1F7A3D, 0x5FD38A), warning: Pair(0x8A5A00, 0xFFEA14), danger: Pair(0xC42B1C, 0xFF6B5B),
        dangerSoft: Pair(0xFDE8E6, 0x3D2220), badge: Pair(0xE0261B, 0xFF3B30), onBadge: Pair(0xFFFFFF, 0xFFFFFF),
        glass: Pair(0xFFFFFF, 0x141414, alpha: (0.82, 0.82)), wash1: Pair(0xFFFFFF, 0x000000),
        wash2: Pair(0xFFFFFF, 0x000000))
}
