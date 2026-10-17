import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ConfigBundle: Codable {
    var app = "ouch"
    var version = 1
    var config: SavedConfig
    var included: [SavedConfig] = []
}
