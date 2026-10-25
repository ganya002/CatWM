import AppKit
import SwiftUI

struct CurveGraph: View {
    let curve: AnimationCurve
    let bounce: Double
    var instant = false
    var lineWidth: CGFloat = 2
    var color: Color = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 4
            let width = size.width - inset * 2, height = size.height - inset * 2
            let samples = (0...120).map { Double($0) / 120 }
            let values = samples.map { instant ? ($0 > 0 ? 1 : 0) : curve.progress($0, bounce: bounce) }
            let low = min(0, values.min() ?? 0), high = max(1, values.max() ?? 1)
            func y(_ value: Double) -> CGFloat { inset + height - CGFloat((value - low) / (high - low)) * height }
            let points = zip(samples, values).map { CGPoint(x: inset + CGFloat($0) * width, y: y($1)) }
            var line = Path()
            for (i, point) in points.enumerated() {
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var area = line
            area.addLine(to: CGPoint(x: inset + width, y: y(0)))
            area.addLine(to: CGPoint(x: inset, y: y(0)))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: inset),
                                                 endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            if let end = points.last {
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(color))
            }
        }
    }
}
