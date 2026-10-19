import AppKit
import CoreText
import SwiftUI

extension View {
    @ViewBuilder func rotateEffect<V: Equatable>(value: V) -> some View {
        if #available(macOS 15.0, *) {
            symbolEffect(.rotate, options: .speed(2.2), value: value)
        } else {
            symbolEffect(.bounce, options: .speed(2), value: value)
        }
    }
    @ViewBuilder func wiggleEffect<V: Equatable>(value: V) -> some View {
        if #available(macOS 15.0, *) {
            symbolEffect(.wiggle, value: value)
        } else {
            symbolEffect(.bounce, value: value)
        }
    }
    @ViewBuilder func breatheEffect(isActive: Bool = true) -> some View {
        if #available(macOS 15.0, *) {
            symbolEffect(.breathe, isActive: isActive)
        } else {
            symbolEffect(.pulse, isActive: isActive)
        }
    }
    @ViewBuilder func drawOnEffect(isActive: Bool) -> some View {
        if #available(macOS 26.0, *) { symbolEffect(.drawOn, isActive: !isActive) } else { self }
    }
}
