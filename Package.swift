// swift-tools-version:5.9
import Foundation
import PackageDescription

// With only the Command Line Tools, the build system sometimes compiles the tests without the Swift
// Testing macro plugin ("plugin for module 'TestingMacros' not found"). Naming its folder fixes that.
let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])] : []

let package = Package(
    name: "ouch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/noxaur/mackeys-sdk.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "ouch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MacKeysCore", package: "mackeys-sdk"),
                .product(name: "MacKeysUI", package: "mackeys-sdk"),
            ],
            path: "Sources/ouch",
            // build.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // `swift test`: config options, and the pure parts of the tiling and Sort code.
        .testTarget(
            name: "ouchTests",
            dependencies: ["ouch"],
            path: "Tests/ouchTests",
            swiftSettings: testSettings
        ),
    ]
)
