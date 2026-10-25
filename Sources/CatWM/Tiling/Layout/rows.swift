import CoreGraphics

func rows(_ rect: CGRect, _ count: Int) -> [CGRect] {
    guard count > 0 else { return [] }
    let height = rect.height / CGFloat(count)
    return (0..<count).map {
        CGRect(x: rect.minX, y: rect.minY + CGFloat($0) * height, width: rect.width, height: height)
    }
}
