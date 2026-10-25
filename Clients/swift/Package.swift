// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CatWMClient",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CatWMClient", targets: ["CatWMClient"])],
    targets: [.target(name: "CatWMClient")]
)
