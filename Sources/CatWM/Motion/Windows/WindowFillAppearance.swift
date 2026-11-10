import AppKit

struct WindowFillAppearance {
    private struct Edges {
        var left: [UInt8] = []
        var right: [UInt8] = []
        var bottom: [UInt8] = []
    }
    private struct ColorBucket {
        var count = 0, red = 0, green = 0, blue = 0
    }
    private struct Contours {
        let outline: CGImage
        let inverse: CGImage
        let border: CGImage
    }

    let leftEdge: CGImage
    let rightEdge: CGImage
    let bottomEdge: CGImage
    let bottomCenter: CGRect
    let outline: CGImage
    let inverseOutline: CGImage
    let border: CGImage
    let center: CGRect
    let sourceSize: CGSize
    let minimumSize: CGSize
    let leftColor: CGColor
    let rightColor: CGColor

    func canFill(from: CGRect, to target: CGRect) -> Bool {
        !from.isNull && !target.isNull && sourceSize.height == from.height && from.minY == target.minY
            && target.size != from.size && from.intersects(target)
            && [from, target].allSatisfy { $0.width >= minimumSize.width && $0.height >= minimumSize.height }
    }

    init?(image: CGImage, size: CGSize) {
        guard image.width > 4, image.height > 4, size.width > 0, size.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        guard let pixels = Self.decode(image, space: space) else { return nil }
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
        let limit = min(width, height) / 2 - 1
        guard let cap = (1..<limit).first(where: { inset in
            [(inset, 0), (width - inset - 1, 0), (inset, height - 1), (width - inset - 1, height - 1)]
                .allSatisfy { alpha($0.0, $0.1) >= 250 }
        }) else { return nil }
        guard (0..<height).allSatisfy({ y in
            (0..<width).allSatisfy { x in
                let corner = (x < cap || x >= width - cap) && (y < cap || y >= height - cap)
                return corner || alpha(x, y) >= 250
            }
        }) else { return nil }
        let side = cap * 2 + 1
        let borderPixels = max(1, Int(ceil(CGFloat(width) / size.width)))
        let edges = Self.edges(pixels, width: width, height: height, cap: cap, border: borderPixels)
        guard let left = Self.image(edges.left, width: 1, height: height, space: space),
              let right = Self.image(edges.right, width: 1, height: height, space: space),
              let bottom = Self.image(edges.bottom, width: width, height: 1, space: space),
              let contours = Self.contours(pixels, image: image, sourceSize: size, cap: cap, space: space),
              let leftColor = Self.color(edges.left, space: space),
              let rightColor = Self.color(edges.right, space: space) else { return nil }
        leftEdge = left
        rightEdge = right
        bottomEdge = bottom
        bottomCenter = Self.stretch(edges.bottom)
        self.leftColor = leftColor
        self.rightColor = rightColor
        outline = contours.outline
        inverseOutline = contours.inverse
        border = contours.border
        center = CGRect(x: CGFloat(cap) / CGFloat(side), y: CGFloat(cap) / CGFloat(side),
                        width: 1 / CGFloat(side), height: 1 / CGFloat(side))
        sourceSize = size
        minimumSize = CGSize(width: CGFloat(cap * 2 + 1) * size.width / CGFloat(width),
                             height: CGFloat(cap * 2 + 1) * size.height / CGFloat(height))
    }

    private static func color(_ pixels: [UInt8], space: CGColorSpace) -> CGColor? {
        CGColor(colorSpace: space, components: pixels.suffix(4).map { CGFloat($0) / 255 })
    }

    private static func stretch(_ pixels: [UInt8]) -> CGRect {
        let width = pixels.count / 4
        var start = 0, bestStart = 0, bestCount = 1
        for x in 1...width {
            if x < width, pixels[(x * 4)..<(x * 4 + 3)] == pixels[(start * 4)..<(start * 4 + 3)] { continue }
            if x - start > bestCount { bestStart = start; bestCount = x - start }
            start = x
        }
        return CGRect(x: CGFloat(bestStart) / CGFloat(width), y: 0,
                      width: CGFloat(bestCount) / CGFloat(width), height: 1)
    }

    private static func edges(_ pixels: [UInt8], width: Int, height: Int, cap: Int,
                              border: Int) -> Edges {
        let inset = min(width / 2 - 1, max(cap, border + 1))
        let span = min(width / 2 - inset, max(4, border * 32))
        let lastRow = max(0, height - border - 2)
        var edges = Edges()
        for y in 0..<height {
            let row = min(y, lastRow)
            edges.left += mode(pixels, indices: (inset..<(inset + span)).map { (row * width + $0) * 4 })
            edges.right += mode(pixels, indices: (inset..<(inset + span)).map { (row * width + width - $0 - 1) * 4 })
        }
        for x in 0..<width {
            let column = min(max(x, inset), width - inset - 1)
            let rows = max(0, lastRow - border * 2)...lastRow
            edges.bottom += mode(pixels, indices: rows.map { ($0 * width + column) * 4 })
        }
        return edges
    }

    private static func mode(_ pixels: [UInt8], indices: [Int]) -> [UInt8] {
        var buckets: [Int: ColorBucket] = [:]
        for index in indices {
            let key = (Int(pixels[index]) >> 3) << 10 | (Int(pixels[index + 1]) >> 3) << 5
                | (Int(pixels[index + 2]) >> 3)
            var bucket = buckets[key] ?? ColorBucket()
            bucket.count += 1
            bucket.red += Int(pixels[index])
            bucket.green += Int(pixels[index + 1])
            bucket.blue += Int(pixels[index + 2])
            buckets[key] = bucket
        }
        guard let winner = buckets.max(by: {
            $0.value.count == $1.value.count ? $0.key > $1.key : $0.value.count < $1.value.count
        })?.value else { return [0, 0, 0, 0] }
        return [winner.red, winner.green, winner.blue].map { UInt8($0 / winner.count) } + [255]
    }

    private static func decode(_ image: CGImage, space: CGColorSpace) -> [UInt8]? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let decoded = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return decoded ? pixels : nil
    }

    private static func contours(_ pixels: [UInt8], image source: CGImage, sourceSize: CGSize,
                                 cap: Int, space: CGColorSpace) -> Contours? {
        let width = source.width, height = source.height
        let borderPixels = max(1, Int(ceil(CGFloat(width) / sourceSize.width)))
        let side = cap * 2 + 1
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
        var positive = [UInt8](repeating: 255, count: side * side * 4)
        var negative = positive
        var border = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            let sourceY = y < cap ? y : y == cap ? height / 2 : height - (side - y)
            for x in 0..<side {
                let sourceX = x < cap ? x : x == cap ? width / 2 : width - (side - x)
                let value = alpha(sourceX, sourceY), index = (y * side + x) * 4
                let interior = (-borderPixels...borderPixels).allSatisfy { offsetY in
                    (-borderPixels...borderPixels).allSatisfy { offsetX in
                        let nextX = sourceX + offsetX, nextY = sourceY + offsetY
                        return nextX >= 0 && nextX < width && nextY >= 0 && nextY < height
                            && alpha(nextX, nextY) >= 250
                    }
                }
                for channel in 0..<4 {
                    positive[index + channel] = value
                    negative[index + channel] = interior ? 0 : 255
                }
                if !interior, value > 0 {
                    let source = (sourceY * width + sourceX) * 4
                    for channel in 0..<3 {
                        border[index + channel] = UInt8(min(255, Int(pixels[source + channel]) * 255 / Int(value)))
                    }
                    border[index + 3] = 255
                }
            }
        }
        guard let positiveImage = image(positive, width: side, height: side, space: space),
              let negativeImage = image(negative, width: side, height: side, space: space),
              let borderImage = image(border, width: side, height: side, space: space) else { return nil }
        return Contours(outline: positiveImage, inverse: negativeImage, border: borderImage)
    }

    private static func image(_ pixels: [UInt8], width: Int, height: Int, space: CGColorSpace) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
