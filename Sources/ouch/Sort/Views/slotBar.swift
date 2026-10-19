import AppKit
import SwiftUI

func slotBar(_ visible: Bool) -> some View {
    Capsule().fill(Theme.accent).frame(width: 3).padding(.vertical, 6).opacity(visible ? 1 : 0).allowsHitTesting(false)
}
