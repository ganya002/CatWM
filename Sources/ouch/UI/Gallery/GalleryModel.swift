#if DEBUG

import AppKit
import SwiftUI

final class GalleryModel: ObservableObject {
    @Published var appearance = GalleryAppearance.system
    @Published var on = true
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
}

#endif
