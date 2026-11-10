import AppKit

extension FillProbeRun {
    func verifySidebar(_ before: NSBitmapImageRep, after: NSBitmapImageRep, label: String,
                       area: CGRect, actual: CGRect) throws {
        if label == "left" {
            let expected = try color(before, x: actual.minX + 80, y: actual.minY + 100, area: area)
            let extended = try color(after, x: actual.minX - 40, y: actual.minY + 100, area: area)
            guard equal(expected, extended) else { throw FillProbeError.pixels("left sidebar became body color") }
            print("left_sidebar_color_extended true")
        }
        if label == "height" {
            for offset in [CGFloat(20), 100, 200, 300, 400] {
                let expected = try color(before, x: actual.minX + offset, y: actual.maxY - 5, area: area)
                let extended = try color(after, x: actual.minX + offset, y: actual.maxY + 40, area: area)
                guard equal(expected, extended) else { throw FillProbeError.pixels("bottom lost sidebar boundary") }
            }
            print("bottom_sidebar_boundary_preserved true")
        }
    }

    func color(_ image: NSBitmapImageRep, x: CGFloat, y: CGFloat, area: CGRect) throws -> NSColor {
        let scale = CGFloat(image.pixelsWide) / area.width
        guard let color = image.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.deviceRGB) else {
            throw FillProbeError.pixels("missing sample")
        }
        return color
    }

    func equal(_ first: NSColor, _ second: NSColor) -> Bool {
        abs(first.redComponent - second.redComponent) < 0.02
            && abs(first.greenComponent - second.greenComponent) < 0.02
            && abs(first.blueComponent - second.blueComponent) < 0.02
    }

    func unchanged(_ before: NSBitmapImageRep, _ after: NSBitmapImageRep,
                   rect: CGRect, area: CGRect, label: String) throws {
        if FillProbeFixture.style == .browser, CommandLine.arguments.contains("--background") {
            try FillProbeCapture.verifyUncovered(rect, area: area)
            print("\(label.replacingOccurrences(of: "unchanged", with: "uncovered")) true")
            return
        }
        guard try matches(before, after, rect: rect, area: area) else {
            throw FillProbeError.pixels(label)
        }
        print("\(label) true")
    }

    func matches(_ before: NSBitmapImageRep, _ after: NSBitmapImageRep,
                 rect: CGRect, area: CGRect) throws -> Bool {
        for y in stride(from: rect.minY, to: rect.maxY, by: 2) {
            for x in stride(from: rect.minX, to: rect.maxX, by: 2) {
                guard try equal(color(before, x: x, y: y, area: area), color(after, x: x, y: y, area: area)) else {
                    return false
                }
            }
        }
        return true
    }

    func verify(before: NSBitmapImageRep, after: NSBitmapImageRep,
                area: CGRect, actual: CGRect, desired: CGRect) throws {
        let local = actual.offsetBy(dx: -area.minX, dy: -area.minY)
        try unchanged(before, after, rect: CGRect(x: local.minX + 5, y: local.minY + 5,
                                                 width: local.width - 50, height: local.height - 50),
                      area: area, label: "live_content_and_traffic_lights_unchanged")
        for offset in [CGFloat(-1), -0.5, 0, 0.5, 1, 2, 4, 8, 16, 40] {
            let sample = try color(after, x: local.maxX + offset, y: local.midY, area: area)
            guard sample.redComponent > 0.98, sample.greenComponent > 0.98, sample.blueComponent > 0.98 else {
                throw FillProbeError.pixels("shadow seam at offset \(offset): \(sample)")
            }
            let bottom = try color(after, x: local.midX, y: local.maxY + offset, area: area)
            guard bottom.redComponent > 0.98, bottom.greenComponent > 0.98, bottom.blueComponent > 0.98 else {
                throw FillProbeError.pixels("bottom shadow seam at offset \(offset): \(bottom)")
            }
        }
        print("shadow_seam_removed true")
        let header = try color(before, x: local.maxX - 35, y: local.minY + 16, area: area)
        let extended = try color(after, x: local.maxX + 40, y: local.minY + 16, area: area)
        guard equal(header, extended) else { throw FillProbeError.pixels("titlebar color mismatch") }
        for row in stride(from: CGFloat(1), through: 48, by: 0.5) {
            let source = try color(before, x: local.maxX - 35, y: local.minY + row, area: area)
            let destination = try color(after, x: local.maxX + 40, y: local.minY + row, area: area)
            guard equal(source, destination) else { throw FillProbeError.pixels("titlebar boundary at row \(row)") }
        }
        print("native_titlebar_color_extended true")
        try verifyOldCorners(before: before, after: after, area: area, actual: actual)
        try verifyClipping(before: before, after: after, area: area, actual: actual, desired: desired)
    }

    func verifyOldCorners(before: NSBitmapImageRep, after: NSBitmapImageRep,
                          area: CGRect, actual: CGRect) throws {
        let local = actual.offsetBy(dx: -area.minX, dy: -area.minY)
        for row in stride(from: CGFloat(0.5), through: 32, by: 0.5) {
            let expected = try color(before, x: local.maxX - 35, y: local.minY + row, area: area)
            for inset in stride(from: CGFloat(0.5), through: 24, by: 0.5) {
                let sample = try color(after, x: local.maxX - inset, y: local.minY + row, area: area)
                guard equal(expected, sample) else {
                    throw FillProbeError.pixels("old titlebar border at inset \(inset), row \(row): \(sample)")
                }
                let left = try color(before, x: local.minX + inset, y: local.midY, area: area)
                let body = try color(before, x: local.maxX - 35, y: local.midY, area: area)
                for (edge, reference) in [(local.minX + inset, left), (local.maxX - inset, body)] {
                    let bottom = try color(after, x: edge, y: local.maxY - row, area: area)
                    guard equal(bottom, reference) else {
                        throw FillProbeError.pixels("old bottom corner at inset \(inset), row \(row)")
                    }
                }
            }
        }
        print("old_corner_borders_removed true")
    }

    func verifyClipping(before: NSBitmapImageRep, after: NSBitmapImageRep,
                        area: CGRect, actual: CGRect, desired: CGRect) throws {
        let target = desired.offsetBy(dx: -area.minX, dy: -area.minY)
        let pixel = area.width / CGFloat(after.pixelsWide)
        for y in stride(from: CGFloat(0), to: area.height, by: pixel) {
            for x in stride(from: CGFloat(0), to: area.width, by: pixel) where !target.contains(CGPoint(x: x, y: y)) {
                guard try equal(color(before, x: x, y: y, area: area), color(after, x: x, y: y, area: area)) else {
                    throw FillProbeError.pixels("fill escaped target at \(x),\(y)")
                }
            }
        }
        try FillProbeCapture.verifyCorners(area: area, actual: actual, desired: desired, window: participant)
        print("outside_bounds_and_native_corners_unchanged true")
    }
}
