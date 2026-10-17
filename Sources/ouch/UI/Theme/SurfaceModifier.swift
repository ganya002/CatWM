import AppKit
import CoreText
import SwiftUI

struct SurfaceModifier: ViewModifier {
    let density: Density
    let glass: Bool
    let caret: Caret

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: density.radius, style: .continuous)
        content
            .padding(density.padding)
            .foregroundStyle(Theme.ink)
            .background(alignment: caretAlignment) { caretView }
            .background { fill(shape) }
    }

    @ViewBuilder private func fill(_ shape: RoundedRectangle) -> some View {
        if glass {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(Theme.glass).background(VisualBlur(radius: density.radius))
                    .background(shape.fill(Color.clear).elevation(density.elevation, in: shape))
            }
        } else {
            shape.fill(Theme.surfaceRaised).elevation(density.elevation, in: shape)
        }
    }

    private var caretAlignment: Alignment {
        switch caret {
        case .bottom, .bottomAt: return .bottom
        case .leadingBottom: return .bottomLeading
        default: return .topLeading
        }
    }

    @ViewBuilder private var caretView: some View {
        let diamond = RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.surfaceRaised)
            .frame(width: 14, height: 14).rotationEffect(.degrees(45))
        switch caret {
        case .none: EmptyView()
        case .top(let x): diamond.offset(x: x - 7, y: -6)
        case .bottom: diamond.offset(y: 6)
        case .bottomAt(let x): diamond.offset(x: x, y: 6)
        case .leading(let y): diamond.offset(x: -6, y: y - 7)
        case .leadingBottom(let y): diamond.offset(x: -6, y: 7 - y)
        }
    }
}
