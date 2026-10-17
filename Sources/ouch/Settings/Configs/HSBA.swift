import AppKit
import SwiftUI

struct HSBA: Equatable {
    var h = 0.12, s = 0.8, b = 1.0, a = 1.0

    var color: Color { Color(hue: h, saturation: s, brightness: b, opacity: a) }
    private var ns: NSColor { NSColor(hue: h, saturation: s, brightness: b, alpha: a).usingColorSpace(.sRGB) ?? .black }
    private var bytes: (Int, Int, Int, Int) {
        let c = ns
        func v(_ x: CGFloat) -> Int { Int((x * 255).rounded()) }
        return (v(c.redComponent), v(c.greenComponent), v(c.blueComponent), v(c.alphaComponent))
    }
    var hexRGB: String { let (r, g, b, _) = bytes; return String(format: "#%02X%02X%02X", r, g, b) }
    var hex: String { let (r, g, b, a) = bytes; return String(format: "%02X%02X%02X%02X", r, g, b, a) }

    init() {}
    init(r: Double, g: Double, b: Double, a: Double = 1) {
        let c = NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, al: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &al)
        self.h = Double(h); self.s = Double(s); self.b = Double(v); self.a = Double(al)
    }

    init?(hex: String) {
        let t = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard t.count == 6 || t.count == 8, let v = UInt64(t, radix: 16) else { return nil }
        let alpha = t.count == 8
        self.init(r: Double((v >> (alpha ? 24 : 16)) & 0xFF) / 255, g: Double((v >> (alpha ? 16 : 8)) & 0xFF) / 255,
                  b: Double((v >> (alpha ? 8 : 0)) & 0xFF) / 255, a: alpha ? Double(v & 0xFF) / 255 : 1)
    }

    init?(text: String) {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        let signed = t.split(whereSeparator: { !"0123456789.-".contains($0) }).compactMap { Double($0) }
        let nums = signed.map { max($0, 0) }
        if t.hasPrefix("rgb"), nums.count >= 3 {
            self.init(r: min(nums[0], 255) / 255, g: min(nums[1], 255) / 255, b: min(nums[2], 255) / 255, a: nums.count > 3 ? min(nums[3], 1) : 1)
        } else if t.hasPrefix("hsl"), nums.count >= 3 {
            let h = (signed[0].truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360, s = min(nums[1], 100) / 100, l = min(nums[2], 100) / 100
            let v = l + s * min(l, 1 - l)
            self.init()
            self.h = h; self.s = v == 0 ? 0 : 2 * (1 - l / v); self.b = v; self.a = nums.count > 3 ? min(nums[3], 1) : 1
        } else if let c = HSBA(hex: t) {
            self = c
        } else {
            return nil
        }
    }
}
