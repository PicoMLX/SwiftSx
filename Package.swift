// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftSx",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        // The search SDK: models, config, backends, manager, rendering.
        // Zero ArgumentParser dependency so embedders (e.g. SwiftBash) can use it.
        .library(name: "SwiftSx", targets: ["SwiftSx"]),
        // The `sx` command tree, for embedders that register it as a builtin.
        .library(name: "SxCommand", targets: ["SxCommand"]),
        // The `sx` executable.
        .executable(name: "sx", targets: ["sx"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Virtualised shell environment: sandboxed filesystem, env vars, stdio.
        .package(url: "https://github.com/Cocoanetics/ShellKit", branch: "main"),
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.3.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SwiftSx",
            dependencies: [
                .product(name: "ShellKit", package: "ShellKit"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
            ]
        ),
        .target(
            name: "SxCommand",
            dependencies: [
                "SwiftSx",
                .product(name: "ShellKit", package: "ShellKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "sx",
            dependencies: ["SxCommand"]
        ),
        .testTarget(
            name: "SwiftSxTests",
            dependencies: ["SwiftSx"]
        ),
        .testTarget(
            name: "SxCommandTests",
            dependencies: ["SxCommand", "SwiftSx"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
