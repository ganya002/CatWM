#if DEBUG

import AppKit
import SwiftUI

struct GallerySearch: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        OSearchField(placeholder: "Search settings", text: $text, shortcut: ["⌘", "K"], focus: $focused)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.surface.opacity(0.6)))
            .frame(width: 320)
    }
}

#endif
