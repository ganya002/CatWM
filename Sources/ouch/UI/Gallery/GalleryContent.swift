#if DEBUG
import AppKit
import SwiftUI

struct GalleryContent {
    @ObservedObject var m: GalleryModel

    func hex(_ path: KeyPath<Palette, Palette.Pair>) -> String {
        let p = Theme.palette[keyPath: path]
        return String(format: "%06X / %06X", p.light, p.dark)
    }
    func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
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
