import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct WhatsNewTextFitTests {
    private func lines(_ text: String, width: CGFloat) -> Int {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 1.5
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13.5),
                                                               .paragraphStyle: style])
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: width, height: 1000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.glyphRange(for: container)
        var count = 0, index = 0
        while index < layout.numberOfGlyphs {
            var range = NSRange()
            layout.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
            index = NSMaxRange(range)
            count += 1
        }
        return count
    }

    @Test func everyFeatureTextFitsTwoLines() {
        let width = WhatsNewView.width - 40 - 18 - 10
        for feature in Release.all.flatMap(\.features) {
            #expect(lines(feature.text, width: width) <= 2, "\(feature.id) needs more than two lines")
        }
    }
}
