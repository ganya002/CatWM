#if DEBUG

import AppKit
import SwiftUI

struct GallerySearch: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        OSearchField.galleryExample(text: $text, focus: $focused)
    }
}

#endif
