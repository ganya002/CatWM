import CoreGraphics

func rows(_ r: CGRect, _ n: Int) -> [CGRect] {
    guard n > 0 else { return [] }
    let h = r.height / CGFloat(n)
    return (0..<n).map { CGRect(x: r.minX, y: r.minY + CGFloat($0) * h, width: r.width, height: h) }
}
