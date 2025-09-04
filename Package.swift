// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UWBViewerSystem",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "UWBViewerSystem",
            targets: ["UWBViewerSystem"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-format.git", from: "509.0.0"),
        .package(url: "https://github.com/google/nearby.git", branch: "main")
    ],
    targets: [
        .target(
            name: "UWBViewerSystem",
            dependencies: [
                .product(name: "NearbyConnections", package: "nearby")
            ],
            path: "UWBViewerSystem",
            exclude: ["UWBViewerSystemApp.swift"],
            resources: [
                .process("Assets.xcassets"),
                .copy("UWBViewerSystem.entitlements")
            ]
        ),
        .testTarget(
            name: "UWBViewerSystemTests",
            dependencies: ["UWBViewerSystem"],
            path: "UWBViewerSystemTests"
        ),
    ]
)