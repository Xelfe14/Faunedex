// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FlaunedexCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "FlaunedexCore", targets: ["FlaunedexCore"]),
    ],
    targets: [
        .target(
            name: "FlaunedexCore"
        ),
        .testTarget(
            name: "FlaunedexCoreTests",
            dependencies: ["FlaunedexCore"]
        ),
    ]
)
