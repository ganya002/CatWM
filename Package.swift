// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hyprthyst",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
    ],
    targets: [
        .executableTarget(
            name: "Hyprthyst",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Hyprthyst",
            // build.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
