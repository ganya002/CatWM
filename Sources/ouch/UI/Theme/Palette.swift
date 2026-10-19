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

    var background, surface, surfaceRaised, surfaceSunken, hover, hairline, borderControl: Pair
    var ink, inkMuted, inkFaint: Pair
    var accent, accentHover, onAccent, accentInk, accentSoft, tint, focus: Pair
    var success, warning, danger, dangerSoft: Pair
    var glass, wash1, wash2: Pair

    static let ouch = Palette(
        background: Pair(0xF4F4F6, 0x1B1B1E), surface: Pair(0xFFFFFF, 0x232326),
        surfaceRaised: Pair(0xFFFFFF, 0x2C2C30),
        surfaceSunken: Pair(0xECECF0, 0x18181B), hover: Pair(0xECECF0, 0x36363B), hairline: Pair(0xE2E2E7, 0x38383D),
        borderControl: Pair(0x7E7E87, 0x7A7A82),
        ink: Pair(0x18181B, 0xF5F5F7), inkMuted: Pair(0x55555C, 0xB4B4BB), inkFaint: Pair(0x68686F, 0x97979F),
        accent: Pair(0x0A68E6, 0x3F95FF), accentHover: Pair(0x0A58C4, 0x5AA8FF), onAccent: Pair(0xFFFFFF, 0x0B0B0D),
        accentInk: Pair(0x0A5FD1, 0x8DC3FF), accentSoft: Pair(0xE3EEFF, 0x1B2C47),
        tint: Pair(0xC7C7CC, 0x4A4A50), focus: Pair(0x0A68E6, 0x8DC3FF),
        success: Pair(0x1F7A3D, 0x5FD38A), warning: Pair(0x8A5A00, 0xFFCC00), danger: Pair(0xC42B1C, 0xFF7B6B),
        dangerSoft: Pair(0xFDE8E6, 0x3D2220),
        glass: Pair(0xFFFFFF, 0x2C2C30, alpha: (0.82, 0.80)), wash1: Pair(0xDDE9FB, 0x1F2C42),
        wash2: Pair(0xE5E5E8, 0x2B2B2F))
}
