// swift-tools-version:5.9
import Foundation
import PackageDescription

let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])] : []

let package = Package(
    name: "MinimalCat",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MinimalCatCore"),
        .target(name: "MinimalCatSystem", dependencies: ["MinimalCatCore"]),
        .executableTarget(name: "MinimalCat", dependencies: ["MinimalCatCore", "MinimalCatSystem"]),
        .executableTarget(name: "minimalcat-check", dependencies: ["MinimalCatCore", "MinimalCatSystem"]),
        .testTarget(name: "MinimalCatCoreTests", dependencies: ["MinimalCatCore"], swiftSettings: testSettings)
    ]
)
