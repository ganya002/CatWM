import AppKit
import CatWMKit
import SwiftUI

struct OPageTitle<Trailing: View>: View {
    let crumbs: [String]
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.small) {
            HStack(spacing: 6) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { i, crumb in
                    if i > 0 { Image(systemName: "chevron.right").font(Theme.symbol(Theme.Icon.extraSmall, .semibold)) }
                    Text(crumb)
                }
            }
            .textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            Spacer(minLength: Theme.Space.medium)
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
extension GalleryExamples {
    static let moreControls = GalleryExample(order: 6) { AnyView(GalleryContent(model: $0).moreControls) }
}

extension GalleryContent {
    @ViewBuilder var moreControls: some View {
        block("More controls") {
            OPageTitle(crumbs: ["Settings", "Layout"]) {
                OButton("Reset", size: .small) {}
            }
            .frame(maxWidth: 560)
            GallerySearch(text: $model.search)
            HStack(spacing: Theme.Space.extraLarge) {
                knobExamples
                segmentTrackExamples
            }
            HStack(spacing: Theme.Space.extraLarge) {
                removeExamples
                pressScaleExample
            }
            essentialExamples
            stepExamples
        }
    }
}
#endif

extension OPageTitle where Trailing == EmptyView {
    init(crumbs: [String]) { self.init(crumbs: crumbs) { EmptyView() } }
}
