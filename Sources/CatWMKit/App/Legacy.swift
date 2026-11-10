import Foundation

package enum Legacy {
    package static let bundlePrefixes = ["local.ouch", "local.hyprthyst"]
    package static let configMarker = "ouch"
    package static let configExtension = "ouchconfig"

    package static func isBundle(_ bundle: String) -> Bool {
        bundlePrefixes.contains { bundle.hasPrefix($0) }
    }
}
