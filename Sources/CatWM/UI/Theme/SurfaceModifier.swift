import AppKit
import CatWMKit
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
    static let surfaces = GalleryExample(order: 8) { AnyView(GalleryContent(model: $0).surfaces) }
}

extension GalleryContent {
    @ViewBuilder var surfaces: some View {
        block("Surfaces") {
            HStack(alignment: .top, spacing: Theme.Space.extraLarge) {
                Text("Retile").font(Theme.body(12.5)).surface(.extraSmall)
                VStack(alignment: .leading, spacing: 2) {
                    Label("Config reloaded", systemImage: "checkmark.circle.fill").font(Theme.body(13.5, .medium))
                    Text("3 binds changed").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                }
                .surface(.small)
                VStack(alignment: .leading, spacing: Theme.Space.extraSmall) {
                    Text("Tip").kicker()
                    Text("Hold ⌥ and drag anywhere in a window to move it.").font(Theme.body())
                        .frame(width: 220, alignment: .leading)
                }
                .padding(Theme.Space.small)
                .surface(.medium)
            }
            HStack(alignment: .top, spacing: Theme.Space.extraLarge) {
                VStack(alignment: .leading, spacing: Theme.Space.small) {
                    Text("Step 2 of 6").kicker()
                    Text("Move focus").textStyle(.title)
                    Text("Use H J K L to jump between windows.").font(Theme.body()).foregroundStyle(Theme.inkMuted)
                    Kbd(keys: ["H"], size: .large)
                }
                .frame(width: 304, alignment: .leading)
                .surface(.large, caret: .top(40))
                VStack(alignment: .leading, spacing: Theme.Space.medium) {
                    Text("Welcome").kicker()
                    Text("Tile without thinking").font(Theme.display(34))
                    Text("CatWM arranges your windows as you open them.").font(Theme.body())
                        .foregroundStyle(Theme.inkMuted)
                    OButton("Continue", variant: .primary, size: .large, shortcut: ["↩"]) {}
                }
                .frame(width: 420, alignment: .leading)
                .surface(.extraLarge)
            }
            .padding(.top, Theme.Space.medium)
        }
    }
}
#endif

enum Density {
    case extraSmall, small, medium, large, extraLarge

    var radius: CGFloat {
        switch self {
        case .extraSmall: Theme.Radius.medium
        case .small, .medium: Theme.Radius.large
        case .large: Theme.Radius.extraLarge
        case .extraLarge: Theme.Radius.xxl
        }
    }
    var padding: EdgeInsets {
        switch self {
        case .extraSmall: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
        case .small: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .medium: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        case .large: EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20)
        case .extraLarge: EdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32)
        }
    }
    var elevation: Elevation { self == .extraSmall || self == .medium ? .popover : .float }
}

extension EdgeInsets {
    init(all inset: CGFloat) { self.init(top: inset, leading: inset, bottom: inset, trailing: inset) }
}

enum Caret: Equatable {
    case none
    case top(CGFloat)
    case bottom
    case bottomAt(CGFloat)
    case leading(CGFloat)
    case leadingBottom(CGFloat)
}

#if DEBUG
extension GalleryExamples {
    static let carets = GalleryExample(order: 9) { AnyView(GalleryContent(model: $0).carets) }
}

extension GalleryContent {
    func caretDemo(_ name: String, _ caret: Caret) -> some View {
        Text(name).font(Theme.body(12.5)).foregroundStyle(Theme.ink).frame(width: 124, height: 40)
            .surface(.medium, caret: caret)
    }

    @ViewBuilder var carets: some View {
        block("Surface carets") {
            HStack(alignment: .top, spacing: Theme.Space.xxl) {
                caretDemo("top(40)", .top(40))
                caretDemo("bottom", .bottom)
                caretDemo("bottomAt(24)", .bottomAt(24))
                caretDemo("leading(20)", .leading(20))
                caretDemo("leadingBottom(24)", .leadingBottom(24))
            }
            .padding(Theme.Space.large)
        }
    }
}
#endif
