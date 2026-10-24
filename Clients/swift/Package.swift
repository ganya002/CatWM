// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OuchClient",
    platforms: [.macOS(.v13)],
    products: [.library(name: "OuchClient", targets: ["OuchClient"])],
    targets: [.target(name: "OuchClient")]
)
