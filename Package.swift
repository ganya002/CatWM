// swift-tools-version:5.9
import Foundation
import PackageDescription

let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])] : []

let package = Package(
    name: "CatWM",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CatWMKit", type: .static, targets: ["CatWMKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/noxaur/mackeys-sdk.git", from: "0.2.0"),
        .package(url: "https://github.com/noxaur/PermissionFlow", branch: "fix/panel-height-wrapping")
    ],
    targets: [
        .plugin(name: "CatalogPlugin", capability: .buildTool()),
        .target(name: "NativeTrafficLight", path: "Sources/native-traffic-light"),
        .target(
            name: "CatWMKit",
            path: "Sources/CatWMKit",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "CatWM",
            dependencies: [
                "CatWMKit",
                "NativeTrafficLight",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MacKeysCore", package: "mackeys-sdk"),
                .product(name: "MacKeysUI", package: "mackeys-sdk"),
                .product(name: "PermissionFlow", package: "PermissionFlow")
            ],
            path: "Sources/CatWM",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])],
            plugins: [.plugin(name: "CatalogPlugin")]
        ),
        .testTarget(
            name: "NativeTrafficLightTests",
            dependencies: ["NativeTrafficLight"],
            path: "Tests/NativeTrafficLightTests",
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "CatWMTests",
            dependencies: ["CatWM", "CatWMKit"],
            path: "Tests/CatWMTests",
            exclude: ["Gallery"],
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "CatWMGalleryTests",
            dependencies: ["CatWM", "CatWMKit"],
            path: "Tests/CatWMTests/Gallery",
            swiftSettings: testSettings
        )
    ]
)
