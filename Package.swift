// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UWBViewerSystem",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "UWBViewerSystem",
            targets: ["UWBViewerSystem"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-format.git", from: "509.0.0")
        // Nearby Connectionsは直接CocoaPodsまたはXcodeプロジェクトの依存関係として管理
    ],
    targets: [
        .target(
            name: "UWBViewerSystem",
            dependencies: [],
            path: "UWBViewerSystem"
        ),
        .testTarget(
            name: "UWBViewerSystemTests",
            dependencies: ["UWBViewerSystem"],
            path: "UWBViewerSystemTests"
        ),
    ]
)