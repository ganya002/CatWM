import AppKit
import CatWMKit
import SwiftUI

struct OSegment<Lead: View>: View {
    let label: String
    var keys: String?
    var count: Int?
    let selected: Bool
    var hot = false
    var thumb: Namespace.ID?
    let action: () -> Void
    @ViewBuilder var lead: (Color) -> Lead

    var body: some View {
        let ink = selected ? Theme.onAccent : hot ? Theme.accentInk : Theme.inkMuted
        Button(action: action) {
            HStack(spacing: Theme.Space.extraSmall) {
                lead(ink)
                if let keys { Text(keys).font(Theme.keys(12.5, .medium)) }
                if !label.isEmpty { Text(label).font(Theme.body(12.5, selected ? .medium : .regular)).oneLine() }
                if let count {
                    Text("\(count)").font(Theme.body(12)).monospacedDigit()
                        .foregroundStyle(selected ? Theme.onAccent.opacity(0.8) : Theme.inkFaint)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, label.isEmpty ? Theme.Space.small : 12).frame(height: 26)
            .background {
                if selected {
                    if let thumb {
                        Capsule().fill(Theme.accent).matchedGeometryEffect(id: "thumb", in: thumb)
                    } else {
                        Capsule().fill(Theme.accent)
                    }
                } else if hot {
                    Capsule().fill(Theme.accentSoft)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension OSegment where Lead == EmptyView {
    init(label: String, keys: String? = nil, count: Int? = nil, selected: Bool, hot: Bool = false,
         thumb: Namespace.ID? = nil, action: @escaping () -> Void) {
        self.init(label: label, keys: keys, count: count, selected: selected, hot: hot, thumb: thumb,
                  action: action) { _ in EmptyView() }
    }
}

struct OSegmentTrack<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Theme.Space.xxs) { content }
            .padding(3)
            .background(Capsule().fill(Theme.well))
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var segmentTrackExamples: some View {
        OSegmentTrack(title: "Filter") {
            OSegment(label: "All", count: 12, selected: true) {}
            OSegment(label: "Floating", count: 3, selected: false) {}
            OSegment(label: "Needs review", selected: false, hot: true) {}
        }
    }
}
#endif
