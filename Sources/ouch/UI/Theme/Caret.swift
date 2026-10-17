import AppKit
import CoreText
import SwiftUI

enum Caret: Equatable {
    case none
    case top(CGFloat)
    case bottom
    case bottomAt(CGFloat)
    case leading(CGFloat)
    case leadingBottom(CGFloat)
}

#if DEBUG
extension GalleryExamples {
    static let carets = GalleryExample(order: 9) { AnyView(GalleryContent(m: $0).carets) }
}

extension GalleryContent {
    func caretDemo(_ name: String, _ caret: Caret) -> some View {
        Text(name).font(Theme.body(12.5)).foregroundStyle(Theme.ink).frame(width: 124, height: 40).surface(.md, caret: caret)
    }

    @ViewBuilder var carets: some View {
        block("Surface carets") {
            HStack(alignment: .top, spacing: Theme.Space.xxl) {
                caretDemo("top(40)", .top(40))
                caretDemo("bottom", .bottom)
                caretDemo("bottomAt(24)", .bottomAt(24))
                caretDemo("leading(20)", .leading(20))
                caretDemo("leadingBottom(24)", .leadingBottom(24))
            }
            .padding(Theme.Space.lg)
        }
    }
}
#endif
