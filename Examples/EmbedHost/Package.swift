// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EmbedHost",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "CatWM", path: "../..")],
    targets: [
        .executableTarget(
            name: "EmbedHost",
            dependencies: [.product(name: "CatWMKit", package: "CatWM")],
            path: "Sources/EmbedHost"
        )
    ]
)
