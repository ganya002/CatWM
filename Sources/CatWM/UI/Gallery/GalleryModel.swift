#if DEBUG

import AppKit
import CatWMKit
import SwiftUI

final class GalleryModel: ObservableObject {
    @Published var appearance = GalleryAppearance.system
    @Published var isOn = true
    @Published var off = false
    @Published var segment = "Spring"
    @Published var gap = 12.0
    @Published var ratio = 50.0
    @Published var speed = 0.64
    @Published var text = ""
    @Published var layout: Layout? = .tall
    @Published var workspace: String? = "2"
    @Published var search = ""
    @Published var popover = false
    @Published var moved = false
    @Published var essentialOn = true
    @Published var catFeeling = CatFeeling.content
    @Published var catMoves = CatMoves()
}

struct ColorToken: Identifiable {
    let name: String
    let path: KeyPath<Palette, Palette.Pair>
    var id: String { name }
}

enum GalleryAppearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct GallerySearch: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        OSearchField.galleryExample(text: $text, focus: $focused)
    }
}

#endif
