import AppKit
import CatWMKit
import SwiftUI

struct OStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.medium) {
            Text("\(number)").font(Theme.display(20)).foregroundStyle(Theme.ink)
                .frame(width: 14, alignment: .leading)
            Text(Self.styled(text)).font(Theme.body(13.5)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func styled(_ markdown: String, size: CGFloat = 13.5) -> AttributedString {
        var styled = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        for run in styled.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            styled[run.range].inlinePresentationIntent = nil
            styled[run.range].font = Theme.body(size, .medium)
        }
        return styled
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var stepExamples: some View {
        VStack(alignment: .leading, spacing: Theme.Space.medium) {
            OStep(number: 1, text: "Press **H** to focus the window on the left.")
            OStep(number: 2, text: "Press **L** to focus the window on the right.")
        }
    }
}
#endif
