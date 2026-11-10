import AppKit
import CatWMKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct SavedConfig: Codable, Identifiable, Equatable {
    var id: String
    var kind: ConfigKind
    var name: String
    var symbol: String?
    var colorHex: String?
    var text: String
    var keyboardID: String?
    var animationID: String?

    var isBuiltIn: Bool { id.hasPrefix(ConfigLibrary.builtInPrefix) }
}

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

struct ConfigBundle: Codable {
    var app = "catwm"
    var version = 1
    var config: SavedConfig
    var included: [SavedConfig] = []
}

enum ConfigSheet: Identifiable {
    case create(kind: ConfigKind, baseID: String)
    case edit(id: String)
    case export(kind: ConfigKind)

    var id: String {
        switch self {
        case .create(let kind, let baseID): "create.\(kind.rawValue).\(baseID)"
        case .edit(let id): "edit.\(id)"
        case .export(let kind): "export.\(kind.rawValue)"
        }
    }
}
