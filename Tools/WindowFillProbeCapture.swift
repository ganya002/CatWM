import AppKit
import QuartzCore

enum FillProbeCapture {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Capture = @convention(c) (Int32, UnsafePointer<CGWindowID>, Int32, UInt32, CGRect)
        -> Unmanaged<CFArray>?

    static func verifyUncovered(_ rect: CGRect, area: CGRect) throws {
        guard let helper = NSApp.windows.first(where: { $0.isVisible && $0.frame == $0.screen?.frame }) else {
            throw FillProbeError.pixels("missing helper during content check")
        }
        let bitmap = try image(area, windows: [CGWindowID(helper.windowNumber)])
        let scale = CGFloat(bitmap.pixelsWide) / area.width
        for y in stride(from: rect.minY, to: rect.maxY, by: 2) {
            for x in stride(from: rect.minX, to: rect.maxX, by: 2) {
                guard let sample = bitmap.colorAt(x: Int(x * scale), y: Int(y * scale)),
                      sample.alphaComponent == 0 else { throw FillProbeError.pixels("fill covered live content") }
            }
        }
    }

    static func verifyRemoved() throws {
        guard let order = WindowServerList.onScreen() else { throw FillProbeError.captureUnavailable }
        let helpers = NSApp.windows.filter { $0.frame == $0.screen?.frame }
        guard helpers.allSatisfy({ !order.contains(CGWindowID($0.windowNumber)) }) else {
            throw FillProbeError.pixels("closed helper remains on screen")
        }
    }

    static func verifyCorners(area: CGRect, actual: CGRect, desired: CGRect, window: CGWindowID) throws {
        guard let helper = NSApp.windows.first(where: { $0.isVisible && $0.frame == $0.screen?.frame }) else {
            throw FillProbeError.pixels("missing helper during corner check")
        }
        let reference = try image(actual, windows: [window])
        let composite = try image(area, windows: [CGWindowID(helper.windowNumber), window])
        let sourceScale = CGFloat(reference.pixelsWide) / actual.width
        let targetScale = CGFloat(composite.pixelsWide) / area.width
        let target = desired.offsetBy(dx: -area.minX, dy: -area.minY)
        for (sourceX, targetX) in [(CGFloat(1), target.minX + 1), (actual.width - 1, target.maxX - 1)] {
            for (sourceY, targetY) in [(CGFloat(1), target.minY + 1), (actual.height - 1, target.maxY - 1)] {
                let expected = reference.colorAt(x: Int(sourceX * sourceScale), y: Int(sourceY * sourceScale))
                let result = composite.colorAt(x: Int(targetX * targetScale), y: Int(targetY * targetScale))
                guard let expected, let result, abs(expected.alphaComponent - result.alphaComponent) < 0.01 else {
                    throw FillProbeError.pixels("native corner alpha changed at \(targetX),\(targetY)")
                }
            }
        }
    }

    static func inspect(_ arguments: ArraySlice<String>) {
        for argument in arguments {
            guard let id = CGWindowID(argument), let source = WindowSceneCapture.windowImage(id) else {
                fputs("fill inspect: unavailable window \(argument)\n", stderr)
                continue
            }
            let appearance = WindowFillAppearance(image: source.image, size: source.frame.size)
            print("window \(id) appearance_supported \(appearance != nil) size \(source.frame.size)")
        }
    }

    static func background(_ area: CGRect, label: String, window: CGWindowID) throws -> NSBitmapImageRep {
        CATransaction.flush()
        let own = NSApp.windows.filter { $0.isVisible && $0.windowNumber > 0 }
        let helpers = own.filter { $0.frame == $0.screen?.frame }.map { CGWindowID($0.windowNumber) }
        let behind = own.filter { !helpers.contains(CGWindowID($0.windowNumber)) }.map { CGWindowID($0.windowNumber) }
        let bitmap = try image(area, windows: helpers + [window] + behind)
        if label == "after", let helper = helpers.first {
            try verifyOpacity(image(area, windows: [helper]), area: area, window: window)
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw FillProbeError.captureUnavailable
        }
        try data.write(to: URL(fileURLWithPath: "/tmp/catwm-fill-background-\(label).png"))
        return bitmap
    }

    private static func image(_ area: CGRect, windows: [CGWindowID]) throws -> NSBitmapImageRep {
        guard CGPreflightScreenCaptureAccess(),
              let connection: Connection = symbol("SLSMainConnectionID"),
              let capture: Capture = symbol("SLSHWCaptureWindowListInRect") else {
            throw FillProbeError.captureUnavailable
        }
        let images = windows.withUnsafeBufferPointer { buffer -> [CGImage]? in
            guard let base = buffer.baseAddress else { return nil }
            return capture(connection(), base, Int32(buffer.count), 0, area)?.takeRetainedValue() as? [CGImage]
        }
        guard let image = images?.first else { throw FillProbeError.captureUnavailable }
        return NSBitmapImageRep(cgImage: image)
    }

    private static func verifyOpacity(_ image: NSBitmapImageRep, area: CGRect, window: CGWindowID) throws {
        guard let actual = WindowSceneCapture.currentFrame(window) else { throw FillProbeError.missingWindow }
        let scale = CGFloat(image.pixelsWide) / area.width
        let points = [CGPoint(x: actual.maxX - 0.5, y: actual.minY + 0.5),
                      CGPoint(x: actual.minX + 0.5, y: actual.maxY - 0.5),
                      CGPoint(x: actual.maxX + 4, y: actual.midY),
                      CGPoint(x: actual.midX, y: actual.maxY + 4)]
        for point in points {
            let color = image.colorAt(x: Int((point.x - area.minX) * scale),
                                      y: Int((point.y - area.minY) * scale))
            guard let color, color.alphaComponent > 0.99 else {
                throw FillProbeError.pixels("helper cannot hide shadow at \(point)")
            }
        }
        print("native_fill_surface_opaque_at_seams true")
    }
}
