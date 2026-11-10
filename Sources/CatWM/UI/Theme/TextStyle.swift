import AppKit
import CatWMKit
import CoreText
import SwiftUI

enum TextStyle {
    case largeTitle
    case title
    case sectionTitle
    case caption

    var font: Font {
        switch self {
        case .largeTitle: Theme.display(40)
        case .title: Theme.heading(22)
        case .sectionTitle: Theme.heading(15)
        case .caption: Theme.body(12)
        }
    }
    var tracking: CGFloat {
        switch self {
        case .largeTitle: -1
        case .title: -0.2
        case .sectionTitle: 0
        case .caption: 0
        }
    }
}

#if DEBUG
extension GalleryExamples {
    static let type = GalleryExample(order: 1) { AnyView(GalleryContent(model: $0).type) }
}

extension GalleryContent {
    @ViewBuilder var type: some View {
        block("Type") {
            VStack(alignment: .leading, spacing: Theme.Space.medium) {
                Text("CatWM").font(Theme.wordmark(64)).tracking(-1.6)
                Text("Tile without thinking").font(Theme.display(44))
                Text("Move focus with H J K L").textStyle(.title)
                Text("Gaps & padding").font(Theme.heading())
                Text("Main on the left, the rest stacked on the right").font(Theme.body())
                Text("Applies to new windows only").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                Text("Behavior").textStyle(.sectionTitle).foregroundStyle(Theme.inkMuted)
                Text("⌘ ⇧ W   ⌘ ⇥   H J K L").font(Theme.keys(12, .medium))
                Text("Step 2 of 6").kicker()
                Text("bind = $mod, H, movefocus, l").font(Theme.mono(12, .regular))
            }
            .foregroundStyle(Theme.ink)
        }
    }
}
#endif

extension Text {
    func textStyle(_ style: TextStyle) -> Text { font(style.font).tracking(style.tracking) }
}

extension View {
    func oneLine(_ mode: Text.TruncationMode = .tail) -> some View { lineLimit(1).truncationMode(mode) }

    func kicker(_ color: Color = Theme.inkMuted) -> some View {
        font(Theme.heading(12)).tracking(0.6).textCase(.uppercase).foregroundStyle(color)
    }

    func textStyle(_ style: TextStyle) -> some View { font(style.font).tracking(style.tracking) }
}
