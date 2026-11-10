#if DEBUG
import AppKit
import CatWMKit
import SwiftUI

struct GalleryContent {
    @ObservedObject var model: GalleryModel

    func hex(_ path: KeyPath<Palette, Palette.Pair>) -> String {
        let pair = Theme.palette[keyPath: path]
        return String(format: "%06X / %06X", pair.light, pair.dark)
    }
    func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.medium) {
            OSectionHeader(title)
            content()
        }
    }
}

struct GalleryExample: Identifiable {
    let order: Int
    let content: (GalleryModel) -> AnyView
    var id: Int { order }
}

enum GalleryExamples {}
#endif
