import AppKit
import CatWMKit
import SwiftUI

enum SortMetrics {
    static let lane: CGFloat = 176
    static let rowHeight = Theme.rowHeight
    static let minRows = 7
    static let tabIndent: CGFloat = 29
    static let closedIndent: CGFloat = 14
    static let closeExtra = (lane - 16) * 10 / 16 + 8 + 24 + 8
    static let closeGap = Theme.Space.medium
}

struct SortZoneKey: PreferenceKey {
    static var defaultValue: [SortZone: CGRect] = [:]
    static func reduce(value: inout [SortZone: CGRect], nextValue: () -> [SortZone: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func zone(_ z: SortZone) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: SortZoneKey.self, value: [z: geo.frame(in: .named("sort"))])
        })
    }

    func keepInside(_ origin: CGPoint) -> some View { KeepInside(origin: origin) { self } }
}

struct KeepInside: SwiftUI.Layout {
    let origin: CGPoint
    private let margin: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews _: SwiftUI.LayoutSubviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: SwiftUI.LayoutSubviews,
                       cache _: inout ()) {
        guard let ghost = subviews.first else { return }
        let size = ghost.sizeThatFits(.unspecified)
        let x = max(margin, min(origin.x, bounds.width - size.width - margin))
        let y = max(margin, min(origin.y, bounds.height - size.height - margin))
        ghost.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: .unspecified)
    }
}

func slotBar(_ visible: Bool) -> some View {
    Capsule().fill(Theme.accent).frame(width: 3).padding(.vertical, 6).opacity(visible ? 1 : 0).allowsHitTesting(false)
}
