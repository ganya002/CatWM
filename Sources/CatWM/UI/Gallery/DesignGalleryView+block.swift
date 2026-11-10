#if DEBUG
import AppKit
import CatWMKit
import SwiftUI

extension DesignGalleryView {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.extraLarge) {
                header
                ForEach(GalleryExamples.all) { example in example.content(model) }
            }
            .padding(Theme.Space.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .accessibilityHidden(true)
        .onChange(of: model.appearance) { _, new in setAppearance(new.appearance) }
    }
}
#endif
