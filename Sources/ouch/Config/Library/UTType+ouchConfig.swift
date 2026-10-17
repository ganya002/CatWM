import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ouchConfig = UTType(filenameExtension: "ouchconfig", conformingTo: .json) ?? .json
}
