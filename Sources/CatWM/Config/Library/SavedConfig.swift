import AppKit
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
