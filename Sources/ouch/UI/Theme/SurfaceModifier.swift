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

#if DEBUG
extension GalleryExamples {
    static let surfaces = GalleryExample(order: 8) { AnyView(GalleryContent(m: $0).surfaces) }
}

extension GalleryContent {
    @ViewBuilder var surfaces: some View {
        block("Surfaces") {
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                Text("Retile").font(Theme.body(12.5)).surface(.xs)
                VStack(alignment: .leading, spacing: 2) {
                    Label("Config reloaded", systemImage: "checkmark.circle.fill").font(Theme.body(13.5, .medium))
                    Text("3 binds changed").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                }
                .surface(.sm)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Tip").kicker()
                    Text("Hold ⌥ and drag anywhere in a window to move it.").font(Theme.body()).frame(width: 220, alignment: .leading)
                }
                .padding(Theme.Space.sm)
                .surface(.md)
            }
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Step 2 of 6").kicker()
                    Text("Move focus").textStyle(.title)
                    Text("Use H J K L to jump between windows.").font(Theme.body()).foregroundStyle(Theme.inkMuted)
                    Kbd(keys: ["H"], size: .large)
                }
                .frame(width: 304, alignment: .leading)
                .surface(.lg, caret: .top(40))
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Welcome").kicker()
                    Text("Tile without thinking").font(Theme.display(34))
                    Text("Ouch arranges your windows as you open them.").font(Theme.body()).foregroundStyle(Theme.inkMuted)
                    OButton("Continue", variant: .primary, size: .lg, shortcut: ["↩"]) {}
                }
                .frame(width: 420, alignment: .leading)
                .surface(.xl)
            }
            .padding(.top, Theme.Space.md)
        }
    }
}
#endif
