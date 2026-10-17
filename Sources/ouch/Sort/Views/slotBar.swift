import AppKit
import SwiftUI

func slotBar(_ on: Bool) -> some View {
    Capsule().fill(Theme.accent).frame(width: 3).padding(.vertical, 6).opacity(on ? 1 : 0).allowsHitTesting(false)
}
