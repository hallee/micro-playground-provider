// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "MicroPlaygroundProvider",
    products: [
        .library(name: "MicroPlaygroundProvider", targets: ["MicroPlaygroundProvider"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0")
    ],
    targets: [
        .target(name: "MicroPlaygroundProvider", dependencies: ["Vapor", "SPMUtility"])
    ]
)
