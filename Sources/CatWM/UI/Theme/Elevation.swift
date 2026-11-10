import AppKit
import CatWMKit
import CoreText
import SwiftUI

enum Elevation: CaseIterable {
    case small, knob, popover, float

    var radius: CGFloat {
        switch self {
        case .small: 1
        case .knob: 2
        case .popover: 13
        case .float: 22
        }
    }

    var y: CGFloat {
        switch self {
        case .small: 1
        case .knob: 0
        case .popover: 10
        case .float: 18
        }
    }

    var room: CGFloat { radius * 2 + y }
}

#if DEBUG
extension GalleryExamples {
    static let shape = GalleryExample(order: 2) { AnyView(GalleryContent(model: $0).shape) }
}

extension GalleryContent {
    @ViewBuilder var shape: some View {
        block("Radius, space and elevation") {
            HStack(alignment: .top, spacing: Theme.Space.extraLarge) {
                ForEach(GalleryMetrics.radii, id: \.0) { name, value in
                    VStack(spacing: Theme.Space.extraSmall) {
                        RoundedRectangle(cornerRadius: value, style: .continuous).fill(Theme.tint)
                            .frame(width: 56, height: 56)
                        Text(name).font(Theme.body(12, .medium))
                        Text("\(Int(value))").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: Theme.Space.large) {
                ForEach(GalleryMetrics.spaces, id: \.0) { name, value in
                    VStack(spacing: Theme.Space.extraSmall) {
                        Rectangle().fill(Theme.accent).frame(width: value, height: 14)
                        Text(name).font(Theme.body(12, .medium))
                        Text("\(Int(value))").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            HStack(spacing: Theme.Space.extraLarge) {
                ForEach(Elevation.allCases, id: \.self) { elevation in
                    let name = String(describing: elevation)
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    Text(name).font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                        .frame(width: 110, height: 64)
                        .background(shape.fill(Theme.surfaceRaised))
                        .elevation(elevation, in: shape)
                        .padding(elevation.room)
                }
            }
            HStack(spacing: Theme.Space.extraLarge) {
                ForEach([("well", Theme.well), ("wellHover", Theme.wellHover), ("thumbMain", Theme.thumbMain)],
                        id: \.0) { name, color in
                    VStack(alignment: .leading, spacing: Theme.Space.extraSmall) {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(color)
                            .frame(width: 80, height: 28)
                        Text(name).font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: Theme.Space.large) {
                ForEach(GalleryMetrics.icons,
                        id: \.0) { name, size in
                    VStack(spacing: Theme.Space.extraSmall) {
                        Image(systemName: "gearshape").font(Theme.symbol(size)).foregroundStyle(Theme.ink)
                        Text("icon \(name)").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }
}
#endif

extension View {
    func elevation<S: Shape>(_ elevation: Elevation, in shape: S, outlined: Bool = true) -> some View {
        let ring = Theme.hairline
        let drop = Color(nsColor: NSColor(name: nil) { appearance in
            let dark = Theme.isDark(appearance)
            switch elevation {
            case .small: return NSColor.black.withAlphaComponent(dark ? 0.4 : 0.06)
            case .knob: return NSColor.black.withAlphaComponent(0.32)
            case .popover: return NSColor.black.withAlphaComponent(dark ? 0.65 : 0.22)
            case .float: return NSColor.black.withAlphaComponent(dark ? 0.75 : 0.35)
            }
        })
        return self
            .overlay(shape.stroke(ring, lineWidth: outlined && (elevation == .popover || elevation == .float) ? 1 : 0))
            .shadow(color: drop, radius: elevation.radius, y: elevation.y)
    }

    func legible(strong: Bool = false) -> some View {
        shadow(color: .black.opacity(strong ? 0.45 : 0.3), radius: strong ? 8 : 12, y: strong ? 2 : 4)
    }
}
