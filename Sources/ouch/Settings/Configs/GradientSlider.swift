import AppKit
import SwiftUI

struct GradientSlider: View {
    @Binding var value: Double
    let colors: [Color]
    let knob: Color
    var checker = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if checker { Canvas { ctx, size in
                    let side: CGFloat = 6
                    for x in 0..<Int(size.width / side) + 1 {
                        for y in 0..<Int(size.height / side) + 1 where (x + y).isMultiple(of: 2) {
                            let cell = CGRect(x: CGFloat(x) * side, y: CGFloat(y) * side, width: side, height: side)
                            ctx.fill(Path(cell),
                                     with: .color(.gray.opacity(0.3)))
                        }
                    }
                }.clipShape(Capsule()) }
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                OKnob(color: knob, size: 18).offset(x: value * (geo.size.width - 18))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(max((drag.location.x - 9) / (geo.size.width - 18), 0), 1)
            })
        }
        .frame(height: 18)
    }
}
