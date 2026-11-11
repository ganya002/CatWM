import CoreGraphics

struct NativeBufferGeometry {
    let size: CGSize
    let surface: CGRect
    let scale: CGFloat
    let pixels: CGRect

    init?(pixels: CGSize, content: [String: Any], scale: CGFloat, contentScale: CGFloat) {
        guard let rect = CGRect(dictionaryRepresentation: content as CFDictionary) else { return nil }
        self.init(pixels: pixels, content: rect, scale: scale, contentScale: contentScale)
    }

    init?(pixels: CGSize, content: CGRect, scale: CGFloat, contentScale: CGFloat) {
        guard scale > 0, abs(contentScale - 1) < 0.001, !content.isNull,
              content.width > 0, content.height > 0 else { return nil }
        let rect = CGRect(x: content.minX * scale, y: content.minY * scale,
                          width: content.width * scale, height: content.height * scale)
        guard CGRect(origin: .zero, size: pixels).insetBy(dx: -0.5, dy: -0.5).contains(rect) else { return nil }
        size = content.size
        surface = CGRect(x: -content.minX, y: -content.minY, width: pixels.width / scale, height: pixels.height / scale)
        self.scale = scale
        self.pixels = rect
    }
}
