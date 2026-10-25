import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum ConfigKind: String, Codable, CaseIterable {
    case keyboard, animation, full

    var title: String {
        switch self {
        case .keyboard: "Keyboard"
        case .animation: "Animation"
        case .full: "Full"
        }
    }
    var noun: String {
        switch self {
        case .keyboard: "shortcuts"
        case .animation: "animations"
        case .full: "settings"
        }
    }
    var genericSymbol: String {
        switch self {
        case .keyboard: "keyboard"
        case .animation: "wand.and.stars"
        case .full: "square.stack.3d.up"
        }
    }
}
