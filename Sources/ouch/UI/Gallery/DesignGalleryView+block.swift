#if DEBUG
import AppKit
import SwiftUI

extension DesignGalleryView {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                ForEach(GalleryExamples.all) { example in example.content(m) }
            }
            .padding(Theme.Space.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .accessibilityHidden(true)
        .onChange(of: m.appearance) { _, new in setAppearance(new.appearance) }
    }
}
#endif
