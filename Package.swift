// swift-tools-version:5.9
import Foundation
import PackageDescription

let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])] : []

let package = Package(
    name: "ouch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/noxaur/mackeys-sdk.git", from: "0.2.0")
    ],
    targets: [
        .plugin(name: "CatalogPlugin", capability: .buildTool()),
        .target(name: "WindowSession", path: "Sources/WindowSession"),
        .executableTarget(
            name: "ouch",
            dependencies: [
                "WindowSession",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MacKeysCore", package: "mackeys-sdk"),
                .product(name: "MacKeysUI", package: "mackeys-sdk")
            ],
            path: "Sources/ouch",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])],
            plugins: [.plugin(name: "CatalogPlugin")]
        ),
        .testTarget(
            name: "WindowSessionTests",
            dependencies: ["WindowSession"],
            path: "Tests/WindowSessionTests",
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "ouchTests",
            dependencies: ["ouch", "WindowSession"],
            path: "Tests/ouchTests",
            swiftSettings: testSettings
        )
    ]
)
