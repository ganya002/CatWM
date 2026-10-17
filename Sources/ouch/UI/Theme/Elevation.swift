import AppKit
import CoreText
import SwiftUI

enum Elevation: CaseIterable {
    case sm, knob, popover, float

    var radius: CGFloat {
        switch self {
        case .sm: 1
        case .knob: 2
        case .popover: 13
        case .float: 22
        }
    }

    var y: CGFloat {
        switch self {
        case .sm: 1
        case .knob: 0
        case .popover: 10
        case .float: 18
        }
    }

    var room: CGFloat { radius * 2 + y }
}

#if DEBUG
extension GalleryExamples {
    static let shape = GalleryExample(order: 2) { AnyView(GalleryContent(m: $0).shape) }
}

extension GalleryContent {
    @ViewBuilder var shape: some View {
        block("Radius, space and elevation") {
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                ForEach(GalleryMetrics.radii, id: \.0) { name, value in
                    VStack(spacing: Theme.Space.xs) {
                        RoundedRectangle(cornerRadius: value, style: .continuous).fill(Theme.tint).frame(width: 56, height: 56)
                        Text(name).font(Theme.body(12, .medium))
                        Text("\(Int(value))").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: Theme.Space.lg) {
                ForEach(GalleryMetrics.spaces, id: \.0) { name, value in
                    VStack(spacing: Theme.Space.xs) {
                        Rectangle().fill(Theme.accent).frame(width: value, height: 14)
                        Text(name).font(Theme.body(12, .medium))
                        Text("\(Int(value))").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            HStack(spacing: Theme.Space.xl) {
                ForEach(Elevation.allCases, id: \.self) { e in
                    let name = String(describing: e)
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    Text(name).font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                        .frame(width: 110, height: 64)
                        .background(shape.fill(Theme.surfaceRaised))
                        .elevation(e, in: shape)
                        .padding(e.room)
                }
            }
            HStack(spacing: Theme.Space.xl) {
                ForEach([("well", Theme.well), ("wellHover", Theme.wellHover), ("thumbMain", Theme.thumbMain)], id: \.0) { name, color in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(color).frame(width: 80, height: 28)
                        Text(name).font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: Theme.Space.lg) {
                ForEach(GalleryMetrics.icons,
                        id: \.0) { name, size in
                    VStack(spacing: Theme.Space.xs) {
                        Image(systemName: "gearshape").font(Theme.symbol(size)).foregroundStyle(Theme.ink)
                        Text("icon \(name)").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }
}
#endif
