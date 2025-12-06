// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "AppVitalityKit",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "AppVitalityKit",
            targets: ["AppVitalityKit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppVitalityKit",
            dependencies: []),
        .testTarget(
            name: "AppVitalityKitTests",
            dependencies: ["AppVitalityKit"]),
    ]
)

