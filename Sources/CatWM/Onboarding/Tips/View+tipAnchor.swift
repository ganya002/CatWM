import AppKit
import SwiftUI

extension View {
    func tipAnchor(_ id: String) -> some View {
        anchorPreference(key: TipAnchorKey.self, value: .bounds) { [id: $0] }
    }
}
