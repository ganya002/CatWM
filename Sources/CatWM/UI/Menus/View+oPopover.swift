import AppKit
import SwiftUI

extension View {
    func oPopover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        modifier(PopoverModifier(isPresented: isPresented, content: content))
    }
}
