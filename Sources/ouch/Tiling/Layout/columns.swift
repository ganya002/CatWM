import CoreGraphics

func columns(_ rect: CGRect, _ count: Int) -> [CGRect] {
    guard count > 0 else { return [] }
    let width = rect.width / CGFloat(count)
    return (0..<count).map {
        CGRect(x: rect.minX + CGFloat($0) * width, y: rect.minY, width: width, height: rect.height)
    }
}
