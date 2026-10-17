import AppKit
import SwiftUI

struct OStep: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(Theme.display(20)).foregroundStyle(Theme.accentInk).frame(width: 14, alignment: .leading)
            Text(Self.styled(text)).font(Theme.body(13.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func styled(_ markdown: String, size: CGFloat = 13.5) -> AttributedString {
        var s = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        for run in s.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            s[run.range].inlinePresentationIntent = nil
            s[run.range].font = Theme.body(size, .medium)
        }
        return s
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var stepExamples: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            OStep(n: 1, text: "Press **H** to focus the window on the left.")
            OStep(n: 2, text: "Press **L** to focus the window on the right.")
        }
    }
}
#endif
