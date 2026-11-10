import AppKit
import CatWMKit
import SwiftUI

final class SplitGripModel: ObservableObject {
    @Published var vertical = true
    @Published var confirming: Bool
    var dragging = false

    init(confirming: Bool = false) { self.confirming = confirming }
}

struct SplitGrip: View {
    static let hitThickness: CGFloat = 10
    static let badgeSize: CGFloat = 18
    static let width = max(hitThickness, badgeSize)

    private static let thickness: CGFloat = 3
    private static let length: CGFloat = 36
    private static let badgeOffset = length / 2 + Theme.Space.extraSmall + badgeSize / 2
    private static let catchFill = Color.black.opacity(0.01)

    @ObservedObject var model: SplitGripModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let vertical = model.vertical
        ZStack {
            Rectangle()
                .fill(Self.catchFill)
                .frame(width: vertical ? Self.hitThickness : nil, height: vertical ? nil : Self.hitThickness)
            Capsule()
                .fill(Theme.fixed(\.surfaceRaised, dark: false))
                .elevation(.small, in: Capsule())
                .frame(width: vertical ? Self.thickness : Self.length, height: vertical ? Self.length : Self.thickness)
            if model.confirming {
                badge
                    .transition(reduceMotion ? .opacity
                        : .scale(scale: 0.4, anchor: vertical ? .top : .leading).combined(with: .opacity))
                    .offset(x: vertical ? 0 : Self.badgeOffset, y: vertical ? Self.badgeOffset : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? Motion.fade : model.confirming ? Motion.pop : Motion.exit, value: model.confirming)
    }

    private var badge: some View {
        Circle()
            .fill(Theme.fixed(\.surfaceRaised, dark: false))
            .elevation(.small, in: Circle())
            .overlay(
                Image(systemName: model.vertical ? "arrow.left.arrow.right" : "arrow.up.arrow.down")
                    .font(Theme.symbol(Theme.Icon.extraSmall, .semibold))
                    .foregroundStyle(Theme.fixed(\.ink, dark: false))
            )
            .frame(width: Self.badgeSize, height: Self.badgeSize)
    }
}

#if DEBUG
extension GalleryExamples {
    static let splitGrip = GalleryExample(order: 16) { AnyView(GalleryContent(model: $0).splitGrip) }
}

extension GalleryContent {
    @ViewBuilder var splitGrip: some View {
        block("Split handle") {
            HStack(spacing: Theme.Space.extraLarge) {
                ForEach([false, true], id: \.self) { confirming in
                    SplitGrip(model: SplitGripModel(confirming: confirming))
                        .frame(width: SplitGrip.width, height: 120)
                        .background(Theme.tint, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                }
            }
        }
    }
}
#endif
