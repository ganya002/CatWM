import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let catwmConfig = UTType(filenameExtension: "catwmconfig", conformingTo: .json) ?? .json
}
