// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "entrust",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "entrust", targets: ["entrust"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "git@github.com:mfxstudios/claude-code-sdk-swift.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "entrust",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ClaudeCodeSDK", package: "claude-code-sdk-swift"),
            ]
        ),
        .testTarget(
            name: "entrustTests",
            dependencies: ["entrust"]
        ),
    ]
)
