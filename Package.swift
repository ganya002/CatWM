// swift-tools-version:5.9
import Foundation
import PackageDescription

let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])] : []

let package = Package(
    name: "CatWM",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/noxaur/mackeys-sdk.git", from: "0.2.0"),
        .package(url: "https://github.com/noxaur/PermissionFlow", branch: "fix/panel-height-wrapping")
    ],
    targets: [
        .plugin(name: "CatalogPlugin", capability: .buildTool()),
        .target(name: "NativeTrafficLight", path: "Sources/native-traffic-light"),
        .executableTarget(
            name: "CatWM",
            dependencies: [
                "NativeTrafficLight",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MacKeysCore", package: "mackeys-sdk"),
                .product(name: "MacKeysUI", package: "mackeys-sdk"),
                .product(name: "PermissionFlow", package: "PermissionFlow")
            ],
            path: "Sources/CatWM",
            resources: [.copy("Config/Script/sucrase.js")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                             .linkedLibrary("sqlite3")],
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
            dependencies: ["CatWM"],
            path: "Tests/CatWMTests",
            exclude: ["Gallery"],
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "CatWMGalleryTests",
            dependencies: ["CatWM"],
            path: "Tests/CatWMTests/Gallery",
            swiftSettings: testSettings
        )
    ]
)
