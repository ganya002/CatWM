import AppKit
import SwiftUI

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
