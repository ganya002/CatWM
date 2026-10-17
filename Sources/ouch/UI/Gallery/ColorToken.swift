#if DEBUG

import AppKit
import SwiftUI

struct ColorToken: Identifiable {
    let name: String
    let path: KeyPath<Palette, Palette.Pair>
    var id: String { name }

}

#endif
