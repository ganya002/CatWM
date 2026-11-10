import AppKit
import CatWMKit
import SwiftUI

struct OGroup<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                OSectionHeader(title).padding(.bottom, Theme.Space.small)
            }
            _VariadicView.Tree(Separated()) { content }
                .padding(.horizontal, Theme.Space.large)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Theme.surfaceRaised))
            if let footer {
                Text(footer).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                    .padding(.top, Theme.Space.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Separated: _VariadicView_MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(children) { child in
                    child.overlay(alignment: .top) {
                        if child.id != children.first?.id { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    }
                }
            }
        }
    }
}

#if DEBUG
extension GalleryExamples {
    static let rows = GalleryExample(order: 5) { AnyView(GalleryContent(model: $0).rows) }
}

extension GalleryContent {
    @ViewBuilder var rows: some View {
        block("Rows and groups") {
            OGroup("Behavior", footer: "Applies to new windows only.") {
                switchRowExamples
                rowExamples
            }
            .frame(maxWidth: 560)
        }
    }
}
#endif

struct OSectionHeader: View {
    let title: String
    var tone: Color = Theme.ink
    var dot: Color?

    init(_ title: String, tone: Color = Theme.ink, dot: Color? = nil) {
        self.title = title; self.tone = tone; self.dot = dot
    }

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(title).textStyle(.sectionTitle).foregroundStyle(tone).oneLine()
        }
        .accessibilityAddTraits(.isHeader)
    }
}
