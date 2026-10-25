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
                if now {
                    guard let rect = anchor.screenRect else { isPresented = false; return }
                    let binding = $isPresented
                    Popup.shared.popover(from: rect, onClose: { binding.wrappedValue = false }, content: content)
                    state.generation = Popup.shared.generation
                } else {
                    Popup.shared.close(generation: state.generation)
                }
            }
    }
}
