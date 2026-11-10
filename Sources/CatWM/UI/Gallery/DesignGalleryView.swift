#if DEBUG
import AppKit
import CatWMKit
import SwiftUI

struct DesignGalleryView: View {
    let setAppearance: (NSAppearance?) -> Void
    @StateObject var model = GalleryModel()

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Space.extraSmall) {
                Text("Design Gallery").textStyle(.largeTitle).foregroundStyle(Theme.ink)
                Text("Every token and component, drawn by the real code. Rules: docs/design/design-system.md")
                    .textStyle(.caption).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            OSegmented(title: "Appearance", options: GalleryAppearance.allCases.map { ($0, $0.rawValue) },
                       selection: $model.appearance)
        }
    }
}
#endif
