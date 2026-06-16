// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThunderID",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ThunderID", targets: ["ThunderID"]),
        .library(name: "ThunderSwiftUI", targets: ["ThunderSwiftUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/realm/SwiftLint", from: "0.57.0"),
    ],
    targets: [
        .target(
            name: "ThunderID",
            path: "Sources/ThunderID",
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")]
        ),
        .target(
            name: "ThunderSwiftUI",
            dependencies: ["ThunderID"],
            path: "Sources/ThunderSwiftUI",
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")]
        ),
        .testTarget(
            name: "ThunderIDTests",
            dependencies: ["ThunderID"],
            path: "Tests/ThunderIDTests",
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")]
        ),
        .testTarget(
            name: "ThunderSwiftUITests",
            dependencies: ["ThunderSwiftUI"],
            path: "Tests/ThunderSwiftUITests",
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")]
        ),
    ]
)
