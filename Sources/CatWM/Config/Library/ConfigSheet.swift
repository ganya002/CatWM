import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

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
