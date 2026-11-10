import AppKit
import CatWMKit
import CoreText
import SwiftUI

private struct SymbolMotion<V: Equatable>: ViewModifier {
    enum Kind { case rotate, wiggle, breathe }
    let kind: Kind
    let value: V
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        switch kind {
        case .rotate:
            if reduceMotion { content } else if #available(macOS 15.0, *) {
                content.symbolEffect(.rotate, options: .speed(2.2), value: value)
            } else {
                content.symbolEffect(.bounce, options: .speed(2), value: value)
            }
        case .wiggle:
            if reduceMotion { content } else if #available(macOS 15.0, *) {
                content.symbolEffect(.wiggle, value: value)
            } else {
                content.symbolEffect(.bounce, value: value)
            }
        case .breathe:
            if #available(macOS 15.0, *) {
                content.symbolEffect(.breathe, isActive: isActive && !reduceMotion)
            } else {
                content.symbolEffect(.pulse, isActive: isActive && !reduceMotion)
            }
        }
    }
}

extension View {
    func rotateEffect<V: Equatable>(value: V) -> some View {
        modifier(SymbolMotion(kind: .rotate, value: value, isActive: true))
    }
    func wiggleEffect<V: Equatable>(value: V) -> some View {
        modifier(SymbolMotion(kind: .wiggle, value: value, isActive: true))
    }
    func breatheEffect(isActive: Bool = true) -> some View {
        modifier(SymbolMotion(kind: .breathe, value: 0, isActive: isActive))
    }
    @ViewBuilder func drawOnEffect(isActive: Bool) -> some View {
        if #available(macOS 26.0, *) { symbolEffect(.drawOn, isActive: !isActive) } else { self }
    }
}
