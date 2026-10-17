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
        case .create(let k, let b): "create.\(k.rawValue).\(b)"
        case .edit(let id): "edit.\(id)"
        case .export(let k): "export.\(k.rawValue)"
        }
    }
}
