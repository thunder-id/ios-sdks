// swift-tools-version: 5.9
// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let appTarget: Target = .executableTarget(
    name: "Quickstart",
    dependencies: [
        .product(name: "ThunderIDSwiftUI", package: "ios-sdks")
    ],
    path: "Sources",
    resources: [.process("Config.plist")]
)

let package = Package(
    name: "Quickstart",
    platforms: [.iOS(.v16), .macOS(.v13)],
    dependencies: [
        // .package(url: "https://github.com/brionmario/thunderid-ios", branch: "main"),
        .package(path: "../..")
    ],
    targets: [appTarget]
)
