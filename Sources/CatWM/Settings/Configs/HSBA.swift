import AppKit
import CatWMKit
import SwiftUI

struct HSBA: Equatable {
    private struct Bytes {
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Int
    }

    var hue = 0.12, saturation = 0.8, brightness = 1.0, alpha = 1.0

    var color: Color { Color(hue: hue, saturation: saturation, brightness: brightness, opacity: alpha) }
    private var nsColor: NSColor {
        NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha).usingColorSpace(.sRGB) ?? .black
    }
    private var bytes: Bytes {
        let srgb = nsColor
        func byte(_ x: CGFloat) -> Int { Int((x * 255).rounded()) }
        return Bytes(red: byte(srgb.redComponent), green: byte(srgb.greenComponent),
                     blue: byte(srgb.blueComponent), alpha: byte(srgb.alphaComponent))
    }
    var hexRGB: String {
        let rgba = bytes
        return String(format: "#%02X%02X%02X", rgba.red, rgba.green, rgba.blue)
    }
    var hex: String {
        let rgba = bytes
        return String(format: "%02X%02X%02X%02X", rgba.red, rgba.green, rgba.blue, rgba.alpha)
    }

    init() {}
    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        let srgb = NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, opacity: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &opacity)
        self.hue = Double(hue); self.saturation = Double(saturation)
        self.brightness = Double(value); self.alpha = Double(opacity)
    }

    init?(hex: String) {
        let text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let alpha = text.count == 8
        self.init(red: Double((value >> (alpha ? 24 : 16)) & 0xFF) / 255,
                  green: Double((value >> (alpha ? 16 : 8)) & 0xFF) / 255,
                  blue: Double((value >> (alpha ? 8 : 0)) & 0xFF) / 255,
                  alpha: alpha ? Double(value & 0xFF) / 255 : 1)
    }

    init?(text: String) {
        let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
        let signed = lowered.split(whereSeparator: { !"0123456789.-".contains($0) }).compactMap { Double($0) }
        let nums = signed.map { max($0, 0) }
        if lowered.hasPrefix("rgb"), nums.count >= 3 {
            self.init(red: min(nums[0], 255) / 255, green: min(nums[1], 255) / 255,
                      blue: min(nums[2], 255) / 255, alpha: nums.count > 3 ? min(nums[3], 1) : 1)
        } else if lowered.hasPrefix("hsl"), nums.count >= 3 {
            let hue = (signed[0].truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
            let saturation = min(nums[1], 100) / 100, lightness = min(nums[2], 100) / 100
            let value = lightness + saturation * min(lightness, 1 - lightness)
            self.init()
            self.hue = hue; self.saturation = value == 0 ? 0 : 2 * (1 - lightness / value)
            self.brightness = value; self.alpha = nums.count > 3 ? min(nums[3], 1) : 1
        } else if let parsed = HSBA(hex: lowered) {
            self = parsed
        } else {
            return nil
        }
    }
}
