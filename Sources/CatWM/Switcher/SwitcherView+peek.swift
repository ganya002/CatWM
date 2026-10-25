import AppKit
import SwiftUI

extension SwitcherView {
    func peek(_ size: CGSize) -> some View {
        VStack(spacing: Theme.Space.extraSmall) {
            ZStack {
                if let item = model.selected { shot(item).id(item.id).transition(.opacity) }
            }
            .frame(width: size.width, height: size.height)
            .animation(fade, value: model.selected?.id)
            if let item = model.selected { titleLine(item) }
        }
    }

    @ViewBuilder private func shot(_ item: SwitcherItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        if let image = model.previews[item.id] {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .clipShape(shape)
                .matchedGeometryEffect(id: "shot\(item.id)", in: morph)
        } else {
            appIcon(item.pid, size: 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(Theme.well))
        }
    }
}
