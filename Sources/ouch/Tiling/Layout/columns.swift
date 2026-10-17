import CoreGraphics

func columns(_ r: CGRect, _ n: Int) -> [CGRect] {
    guard n > 0 else { return [] }
    let w = r.width / CGFloat(n)
    return (0..<n).map { CGRect(x: r.minX + CGFloat($0) * w, y: r.minY, width: w, height: r.height) }
}
