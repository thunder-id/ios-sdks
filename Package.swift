// swift-tools-version: 5.9
// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "ThunderID",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ThunderID", targets: ["ThunderID"]),
        .library(name: "ThunderIDSwiftUI", targets: ["ThunderIDSwiftUI"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ThunderID",
            path: "Sources/ThunderID"
        ),
        .target(
            name: "ThunderIDSwiftUI",
            dependencies: ["ThunderID"],
            path: "Sources/ThunderIDSwiftUI",
            resources: [
                .copy("Resources/LogoIcons"),
                .copy("Resources/ProviderIcons")
            ]
        ),
        .testTarget(
            name: "ThunderIDTests",
            dependencies: ["ThunderID"],
            path: "Tests/ThunderIDTests"
        ),
        .testTarget(
            name: "ThunderIDSwiftUITests",
            dependencies: ["ThunderIDSwiftUI"],
            path: "Tests/ThunderIDSwiftUITests"
        )
    ]
)
