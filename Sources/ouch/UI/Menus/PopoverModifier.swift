import AppKit
import SwiftUI

struct PopoverModifier<PopContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let content: () -> PopContent
    @StateObject private var anchor = ScreenAnchor()
    @StateObject private var state = PopoverState()

    func body(content view: Content) -> some View {
        view
            .background(AnchorReader(anchor: anchor))
            .onChange(of: isPresented) { _, now in
                if now, let r = anchor.screenRect {
                    let binding = $isPresented
                    Popup.shared.popover(from: r, onClose: { binding.wrappedValue = false }, content: content)
                    state.generation = Popup.shared.generation
                } else if !now {
                    Popup.shared.close(generation: state.generation)
                }
            }
    }
}
